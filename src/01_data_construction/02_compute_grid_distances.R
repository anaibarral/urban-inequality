# ==============================================================================
# 02_compute_grid_distances.R
#
# Step 2 of 6. Geodesic distance from every grid cell centroid to the centroid
# of the urban centre it belongs to. This is the regressor of the gradient
# specifications in step 4.
#
# Input   PATH_UCDB
#         PATHS$grid_centroids   (step 1)
# Output  PATHS$distances        city_id, grid_cell_id, dist_mt (metres)
#
# The city centroid comes from `st_point_on_surface()` rather than
# `st_centroid()`. Urban centre polygons are frequently concave or ring-shaped
# (a bay, a mountain, a river bend), and for those the true centroid can fall
# outside the polygon, which would put the reference point of the gradient in
# unbuilt land. `st_point_on_surface()` is guaranteed to return a point inside.
#
# Distances are geodesic: `sf_use_s2(TRUE)` measures on the ellipsoid, so the
# values are correct at every latitude without a projected CRS per city.
# ==============================================================================

source(here::here("src", "R", "setup.R"))

library(dplyr)
library(sf)
library(arrow)
library(foreach)
library(doParallel)


# ------------------------------------------------------------------------------
# 1. Inputs
# ------------------------------------------------------------------------------

require_input(PATH_UCDB)
require_input(PATHS$grid_centroids, "01_build_urban_centre_grids.R")

log_step("Reading urban centres and grid centroids.")
urban_centres  <- st_read(PATH_UCDB, quiet = TRUE)
grid_centroids <- st_read(PATHS$grid_centroids, quiet = TRUE)

# `st_write()` truncates field names to 10 characters in the shapefile format,
# so `grid_cell_id` comes back as `grd_cll_d`. Restore the full name here rather
# than letting the abbreviation propagate.
names(grid_centroids)[grepl("^grd_c", names(grid_centroids))] <- "grid_cell_id"

city_centroids <- st_point_on_surface(urban_centres)
city_ids <- urban_centres$ID_HDC_G0


# ------------------------------------------------------------------------------
# 2. Distance per city
# ------------------------------------------------------------------------------

cl <- start_cluster()
on.exit(stop_cluster(cl), add = TRUE)

log_step(sprintf("Computing distances for %s cities.",
                 format(length(city_ids), big.mark = ",")))

distances <- foreach(
  i = seq_along(city_ids),
  .packages = c("sf", "dplyr"),
  .combine = "rbind",
  .errorhandling = "remove"
) %dopar% {

  sf::sf_use_s2(TRUE)

  centre <- city_centroids |>
    dplyr::filter(ID_HDC_G0 == city_ids[i]) |>
    sf::st_transform(sf::st_crs(urban_centres))

  grid_centroids |>
    dplyr::filter(city_id == city_ids[i]) |>
    dplyr::mutate(dist_mt = as.numeric(sf::st_distance(geometry, sf::st_geometry(centre)))) |>
    sf::st_drop_geometry() |>
    dplyr::select(city_id, grid_cell_id, dist_mt)
}

if (is.null(distances) || nrow(distances) == 0) {
  stop("No distances were computed.", call. = FALSE)
}

stopifnot(!any(is.na(distances$dist_mt)), all(distances$dist_mt >= 0))

log_step(sprintf("Computed %s cell-to-centroid distances.",
                 format(nrow(distances), big.mark = ",")))


# ------------------------------------------------------------------------------
# 3. Write
# ------------------------------------------------------------------------------

write_parquet(distances, prepare_output(PATHS$distances))
log_step("Wrote ", PATHS$distances)

log_step("Step 2 complete.")
