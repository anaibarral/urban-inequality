# ==============================================================================
# 01_population_centroids.R
#
# Epoch dataset, step 1 of 5. Population-weighted centroid of every urban
# centre polygon of the GHS-UCDB R2024A multitemporal database (MTUC), epoch by
# epoch.
#
# Input   PATH_UCDB_MTUC      one polygon layer per epoch (GHSL_UCDB_MTUC_<year>_GLOBE_R2024)
#         DIR_GHS_POP_MOLL    GHS-POP R2023A, 1 km Mollweide, one raster per epoch
# Output  PATHS$epoch_centroids
#           city_id, year, lon_pwc, lat_pwc, centroid_snapped, pop_total
#
# For each epoch the polygons of THAT epoch are combined with the GHS-POP raster
# of the same year:
#
#     x_c = sum(pop_i * x_i) / sum(pop_i),   y_c = sum(pop_i * y_i) / sum(pop_i)
#
# over the 1 km pixels of the polygon, where pop_i is the pixel's population
# times the share of the pixel inside the polygon. The GHS-POP grid is the grid
# on which GHSL drew the polygons, so no reprojection is involved. The average
# is taken in Mollweide metres and then converted to longitude/latitude.
#
# A weighted average always lies inside the convex hull of the city, but not
# necessarily inside the polygon (cities in several pieces, or around bays and
# rivers). In those cases the centroid is replaced by the nearest point of the
# polygon, and centroid_snapped = 1.
# ==============================================================================

source(here::here("src", "R", "setup.R"))

library(dplyr)
library(sf)
library(terra)
library(arrow)
library(foreach)
library(doParallel)

require_input(PATH_UCDB_MTUC)
pop_files <- resolve_ghs_pop_rasters(BENCHMARK_YEARS, mollweide = TRUE)


# ------------------------------------------------------------------------------
# Centroids, one epoch per worker
# ------------------------------------------------------------------------------

cl <- start_cluster(min(N_CORES, nrow(pop_files)))
on.exit(stop_cluster(cl), add = TRUE)

log_step(sprintf("Computing population-weighted centroids for %d epochs.", nrow(pop_files)))

centroids <- foreach(
  k = seq_len(nrow(pop_files)),
  .packages = c("sf", "terra", "dplyr"),
  .combine = "rbind"
) %dopar% {

  yr <- pop_files$year[k]
  polys <- sf::st_read(PATH_UCDB_MTUC, layer = paste0("GHSL_UCDB_MTUC_", yr, "_GLOBE_R2024"), quiet = TRUE)
  polys <- sf::st_make_valid(polys[, "ID_UC_G0"])

  pop_raster <- terra::rast(pop_files$path[k])
  names(pop_raster) <- "pop"
  stopifnot(sf::st_crs(polys) == sf::st_crs(terra::crs(pop_raster)))

  # Pixels of each polygon. Cropping the raster to each city first is much
  # faster than extracting every city from the global raster at once.
  # exact = TRUE returns the share of each pixel inside the polygon.
  polys_v <- terra::vect(polys)
  pixels <- dplyr::bind_rows(lapply(seq_len(nrow(polys_v)), function(i) {
    r_city <- terra::crop(pop_raster, polys_v[i], snap = "out")
    e <- terra::extract(r_city, polys_v[i], xy = TRUE, exact = TRUE)
    e$ID <- i
    e
  }))

  out <- pixels |>
    dplyr::filter(!is.na(pop)) |>
    dplyr::mutate(pop_in = pop * fraction) |>
    dplyr::group_by(ID) |>
    dplyr::summarise(
      pop_total = sum(pop_in),
      x_pwc     = sum(pop_in * x) / sum(pop_in),
      y_pwc     = sum(pop_in * y) / sum(pop_in)
    ) |>
    dplyr::ungroup() |>
    dplyr::filter(pop_total > 0)

  # Centroids outside their own polygon move to the nearest point of it.
  pts <- sf::st_as_sf(out, coords = c("x_pwc", "y_pwc"), crs = sf::st_crs(polys), remove = FALSE)
  hits <- sf::st_intersects(pts, polys)
  inside <- mapply(function(h, id) id %in% h, hits, out$ID)
  out$centroid_snapped <- as.integer(!inside)

  moved <- which(!inside)
  if (length(moved) > 0) {
    lines <- sf::st_nearest_points(sf::st_geometry(pts)[moved], sf::st_geometry(polys)[out$ID[moved]], pairwise = TRUE)
    end_xy <- sf::st_coordinates(lines)
    end_xy <- end_xy[!duplicated(end_xy[, "L1"], fromLast = TRUE), c("X", "Y"), drop = FALSE]
    out$x_pwc[moved] <- end_xy[, "X"]
    out$y_pwc[moved] <- end_xy[, "Y"]
    pts <- sf::st_as_sf(out, coords = c("x_pwc", "y_pwc"), crs = sf::st_crs(polys), remove = FALSE)
  }

  lonlat <- sf::st_coordinates(sf::st_transform(sf::st_geometry(pts), 4326))

  data.frame(
    city_id          = polys$ID_UC_G0[out$ID],
    year             = yr,
    lon_pwc          = lonlat[, "X"],
    lat_pwc          = lonlat[, "Y"],
    centroid_snapped = out$centroid_snapped,
    pop_total        = out$pop_total
  )
}

centroids <- dplyr::arrange(centroids, city_id, year)

log_step(sprintf("Centroids: %s urban centre-epochs; %s moved to the nearest point of their polygon.",
                 format(nrow(centroids), big.mark = ","), format(sum(centroids$centroid_snapped), big.mark = ",")))

write_parquet(centroids, prepare_output(PATHS$epoch_centroids))
log_step("Wrote ", PATHS$epoch_centroids)
