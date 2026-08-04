# ==============================================================================
# 01_build_urban_centre_grids.R
#
# Step 1 of 6. Turns each urban centre polygon into the set of ~1 km grid cells
# that the rest of the pipeline works on.
#
# For every GHS-UCDB polygon the reference nighttime light raster is cropped and
# masked, converted to one square polygon per pixel, and each pixel is tagged
# with its cell index in the *global* raster. That global index is what lets the
# distance table (step 2) and the extracted values (step 3) be joined on
# (city_id, grid_cell_id) without any spatial operation.
#
# Input   PATH_UCDB
#         first raster in DIR_NTL_DMSP, used only as a geometry template
# Output  PATHS$grids            one square polygon per grid cell
#         PATHS$grid_centroids   the centroid of each of those squares
#
# The template fixes the geometry of every downstream step. The DMSP and VIIRS
# composites are distributed on the same 30 arc-second grid, so a single set of
# grids serves both sources.
# ==============================================================================

source(here::here("src", "R", "setup.R"))

library(dplyr)
library(sf)
library(terra)
library(foreach)
library(doParallel)


# ------------------------------------------------------------------------------
# 1. Inputs and geometry template
# ------------------------------------------------------------------------------

require_input(PATH_UCDB)

log_step("Reading urban centre polygons.")
urban_centres <- st_read(PATH_UCDB, quiet = TRUE)
log_step(sprintf("Loaded %s urban centres.", format(nrow(urban_centres), big.mark = ",")))

ntl_files <- resolve_rasters_by_year(DIR_NTL_DMSP, BENCHMARK_YEARS, label = "DMSP-like NTL")
template_path <- ntl_files$path[1]

template <- terra::rast(template_path)
log_step("Geometry template: ", basename(template_path))
log_step(sprintf("Pixel resolution: %s degrees.",
                 paste(round(terra::res(template), 8), collapse = " x ")))

# The polygons must live in the raster's CRS before cropping.
if (st_crs(urban_centres) != st_crs(template)) {
  log_step("Reprojecting urban centres onto the raster CRS.")
  urban_centres <- st_transform(urban_centres, st_crs(template))
}
rm(template)


# ------------------------------------------------------------------------------
# 2. One set of pixel polygons per urban centre
# ------------------------------------------------------------------------------

cl <- start_cluster()
on.exit(stop_cluster(cl), add = TRUE)

log_step("Building per-city grids.")

grids <- foreach(
  i = seq_len(nrow(urban_centres)),
  .packages = c("sf", "terra", "dplyr"),
  .combine = "rbind",
  # A polygon that does not overlap the raster (small islands, polygons at the
  # edge of the DMSP footprint) yields nothing; drop it and carry on.
  .errorhandling = "remove"
) %dopar% {

  # terra objects cannot cross the process boundary, so each worker opens the
  # raster itself. Only the header is read until values are requested.
  raster <- terra::rast(template_path)
  city   <- urban_centres[i, ]

  # snap = "near" keeps the crop aligned to the existing grid rather than
  # introducing a new origin at the polygon boundary.
  city_raster <- terra::crop(raster, city, snap = "near")
  city_raster <- terra::mask(city_raster, city)

  if (all(is.na(terra::minmax(city_raster)))) return(NULL)

  # dissolve = FALSE keeps one polygon per pixel instead of merging equal values.
  pixels <- sf::st_as_sf(terra::as.polygons(city_raster, dissolve = FALSE, na.rm = TRUE))

  # Recover the index of each pixel in the global raster. Doing this by
  # coordinate lookup rather than by counting guarantees the same identifier
  # that terra::extract() reports in step 3.
  centroid_coords <- sf::st_coordinates(sf::st_centroid(pixels))
  global_cell_ids <- terra::cellFromXY(raster, centroid_coords)

  pixels |>
    dplyr::select() |>
    dplyr::mutate(
      city_id      = city$ID_HDC_G0,
      grid_cell_id = global_cell_ids
    )
}

if (is.null(grids) || nrow(grids) == 0) {
  stop("No grids were generated. Check that the polygons and the raster overlap.",
       call. = FALSE)
}

log_step(sprintf("Generated %s grid cells across %s cities.",
                 format(nrow(grids), big.mark = ","),
                 format(dplyr::n_distinct(grids$city_id), big.mark = ",")))


# ------------------------------------------------------------------------------
# 3. Write grids and centroids
# ------------------------------------------------------------------------------

st_write(grids, prepare_output(PATHS$grids), delete_layer = TRUE, quiet = TRUE)
log_step("Wrote ", PATHS$grids)

centroids <- st_centroid(grids)
coords <- st_coordinates(centroids)
centroids <- centroids |>
  dplyr::mutate(long = coords[, 1], lat = coords[, 2])

st_write(centroids, prepare_output(PATHS$grid_centroids), delete_layer = TRUE, quiet = TRUE)
log_step("Wrote ", PATHS$grid_centroids)

log_step("Step 1 complete.")
