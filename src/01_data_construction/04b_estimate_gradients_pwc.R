# ==============================================================================
# 04b_estimate_gradients_pwc.R
#
# Step 4b. The luminosity gradients of step 4 measured from the
# population-weighted centroid of each city-year instead of the city centroid
# of step 2 (st_point_on_surface on the 2015 polygon).
#
# Input   PATHS$cells_dmsp, PATHS$cells_viirs   (step 3)
#         PATH_UCDB
# Output  PATHS$pwc_centroids                   one row per city-year and population source
#         PATHS$gradients_pwc_{pop,no_pop}_{dmsp,viirs}[_ghs]
#
# THE CENTRE. For each city-year, the mean of the coordinates of its grid cells
# weighted by their population (cells with positive population). The weights
# are the population source of the gradient: GPW for the _gpw columns and
# GHS-POP for the _ghs columns, the same population that enters the cell filter
# and the population control. Centroids outside the polygon (about 1%) are moved
# to the nearest point of the polygon. See src/R/centroids.R.
#
# Everything else is as in step 4: the same cells, filters and specifications,
# estimated by compute_gradients(). Only the distance regressor changes.
# Distances are great-circle distances to the centroid (sphere of 6,371.01 km).
#
# Runtime: about 70 minutes on 20 cores (eight sets of gradients).
# ==============================================================================

source(here::here("src", "R", "setup.R"))
source(here::here("src", "R", "inequality.R"))
source(here::here("src", "R", "centroids.R"))

library(data.table)
library(dplyr)
library(sf)
library(arrow)
library(foreach)
library(doParallel)

require_input(PATHS$cells_dmsp, "03_extract_ntl_and_population.R")
require_input(PATHS$cells_viirs, "03_extract_ntl_and_population.R")
require_input(PATH_UCDB)


# ------------------------------------------------------------------------------
# 1. Centroids and distances, one set per population source
# ------------------------------------------------------------------------------

polys <- st_make_valid(st_read(PATH_UCDB, quiet = TRUE)[, "ID_HDC_G0"])
dm <- as.data.table(read_parquet(PATHS$cells_dmsp))
cell_xy <- unique(dm[, .(city_id, year, grid_cell_id, x, y)])

centroids <- rbindlist(lapply(c(gpw = "pop", ghs = "pop_ghs"), function(p)
  population_weighted_centroids(dm, p, polys)), idcol = "population")
rm(dm); gc()
for (pp in c("gpw", "ghs")) {
  log_step(sprintf("%s centroids moved into their polygon: %d of %d (%.1f%%).", toupper(pp),
                   sum(centroids[population == pp]$moved), nrow(centroids[population == pp]),
                   100 * mean(centroids[population == pp]$moved)))
}
write_parquet(centroids, prepare_output(PATHS$pwc_centroids))

distances_for <- function(pp) {
  d <- merge(cell_xy, centroids[population == pp, .(city_id, year, lon, lat)], by = c("city_id", "year"))
  d[, dist_mt := great_circle_distance(x, y, lon, lat)]
  d[, .(city_id, year, grid_cell_id, dist_mt)]
}


# ------------------------------------------------------------------------------
# 2. Gradients
# ------------------------------------------------------------------------------

specifications <- list(
  list(source = "dmsp",  cells = PATHS$cells_dmsp,  control = TRUE,  pop = "gpw", output = PATHS$gradients_pwc_pop_dmsp),
  list(source = "dmsp",  cells = PATHS$cells_dmsp,  control = FALSE, pop = "gpw", output = PATHS$gradients_pwc_no_pop_dmsp),
  list(source = "viirs", cells = PATHS$cells_viirs, control = TRUE,  pop = "gpw", output = PATHS$gradients_pwc_pop_viirs),
  list(source = "viirs", cells = PATHS$cells_viirs, control = FALSE, pop = "gpw", output = PATHS$gradients_pwc_no_pop_viirs),
  list(source = "dmsp",  cells = PATHS$cells_dmsp,  control = TRUE,  pop = "ghs", output = PATHS$gradients_pwc_pop_dmsp_ghs),
  list(source = "dmsp",  cells = PATHS$cells_dmsp,  control = FALSE, pop = "ghs", output = PATHS$gradients_pwc_no_pop_dmsp_ghs),
  list(source = "viirs", cells = PATHS$cells_viirs, control = TRUE,  pop = "ghs", output = PATHS$gradients_pwc_pop_viirs_ghs),
  list(source = "viirs", cells = PATHS$cells_viirs, control = FALSE, pop = "ghs", output = PATHS$gradients_pwc_no_pop_viirs_ghs)
)

cl <- start_cluster()
on.exit(stop_cluster(cl), add = TRUE)

for (pp in c("gpw", "ghs")) {
  distances <- distances_for(pp)
  for (spec in Filter(function(s) s$pop == pp, specifications)) {
    log_step(sprintf("=== %s gradients from population-weighted centroids, %s population control, %s population ===",
                     toupper(spec$source), if (spec$control) "with" else "without", toupper(spec$pop)))
    cells <- merge(as.data.table(read_parquet(spec$cells)), distances, by = c("city_id", "year", "grid_cell_id"))
    if (spec$pop == "ghs") cells[, pop := pop_ghs]
    gradients <- compute_gradients(as.data.frame(cells), population_control = spec$control)
    log_step(sprintf("Estimated %s city-year gradients. Share negative: %.1f%%.",
                     format(nrow(gradients), big.mark = ","), 100 * mean(gradients$beta_1 < 0)))
    write_parquet(gradients, prepare_output(spec$output))
    rm(cells, gradients); gc()
  }
}

log_step("Step 4b complete.")
