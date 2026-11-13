# ==============================================================================
# 02_grid_distances.R
#
# Epoch dataset, step 2 of 5. The 1 km grid cells of every MTUC polygon, epoch
# by epoch, and the distance from each cell centre to the population-weighted
# centroid of its urban centre in that epoch.
#
# Input   PATH_UCDB_MTUC, DIR_GHS_POP_MOLL
#         PATHS$epoch_centroids   (step 1)
# Output  PATHS$epoch_distances
#           city_id, year, grid_cell_id, dist_mt (metres)
#
# The cells are the pixels of the GHS-POP 1 km Mollweide grid with any part
# inside the polygon. grid_cell_id is the pixel's index in the global raster,
# the same in every epoch, so it joins directly with the extraction of step 3.
#
# Distances are great-circle distances (haversine, with the mean Earth radius
# used by s2) between the cell centre and the centroid, both in
# longitude/latitude.
# ==============================================================================

source(here::here("src", "R", "setup.R"))

library(dplyr)
library(sf)
library(terra)
library(arrow)
library(foreach)
library(doParallel)

require_input(PATH_UCDB_MTUC)
require_input(PATHS$epoch_centroids, "05_epoch_dataset/01_population_centroids.R")
pop_files <- resolve_ghs_pop_rasters(BENCHMARK_YEARS, mollweide = TRUE)
centroids <- read_parquet(PATHS$epoch_centroids) |>
  dplyr::select(city_id, year, lon_pwc, lat_pwc)

dist_haversine <- function(lon1, lat1, lon2, lat2, r = 6371010) {
  rad  <- pi / 180
  dlat <- (lat2 - lat1) * rad
  dlon <- (lon2 - lon1) * rad
  a <- sin(dlat / 2)^2 + cos(lat1 * rad) * cos(lat2 * rad) * sin(dlon / 2)^2
  2 * r * asin(pmin(1, sqrt(a)))
}


# ------------------------------------------------------------------------------
# Cells and distances, one epoch per worker
# ------------------------------------------------------------------------------

cl <- start_cluster(min(N_CORES, nrow(pop_files)))
on.exit(stop_cluster(cl), add = TRUE)

log_step(sprintf("Computing cell distances for %d epochs.", nrow(pop_files)))

distances <- foreach(
  k = seq_len(nrow(pop_files)),
  .packages = c("sf", "terra", "dplyr"),
  .combine = "rbind"
) %dopar% {

  yr <- pop_files$year[k]
  polys <- sf::st_read(PATH_UCDB_MTUC, layer = paste0("GHSL_UCDB_MTUC_", yr, "_GLOBE_R2024"), quiet = TRUE)
  polys <- sf::st_make_valid(polys[, "ID_UC_G0"])

  pop_raster <- terra::rast(pop_files$path[k])
  names(pop_raster) <- "pop"

  polys_v <- terra::vect(polys)
  grids <- dplyr::bind_rows(lapply(seq_len(nrow(polys_v)), function(i) {
    r_city <- terra::crop(pop_raster, polys_v[i], snap = "out")
    e <- terra::extract(r_city, polys_v[i], xy = TRUE, exact = TRUE)
    e$city_id <- polys$ID_UC_G0[i]
    e
  })) |>
    dplyr::filter(fraction > 0)

  grids$grid_cell_id <- terra::cellFromXY(pop_raster, cbind(grids$x, grids$y))
  lonlat <- sf::sf_project(from = sf::st_crs(polys), to = sf::st_crs(4326), pts = cbind(grids$x, grids$y))

  grids |>
    dplyr::mutate(year = yr, lon = lonlat[, 1], lat = lonlat[, 2]) |>
    dplyr::left_join(centroids, by = c("city_id", "year")) |>
    dplyr::mutate(dist_mt = dist_haversine(lon, lat, lon_pwc, lat_pwc)) |>
    dplyr::select(city_id, year, grid_cell_id, dist_mt)
}

n_missing <- sum(is.na(distances$dist_mt))
if (n_missing > 0) log_step(sprintf("%s cells have no population-weighted centroid.", format(n_missing, big.mark = ",")))

log_step(sprintf("Distances: %s cell-epoch records.", format(nrow(distances), big.mark = ",")))
write_parquet(distances, prepare_output(PATHS$epoch_distances))
log_step("Wrote ", PATHS$epoch_distances)
