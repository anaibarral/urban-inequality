# ==============================================================================
# 03_extract_ntl_and_population.R
#
# Epoch dataset, step 3 of 5. Luminosity and population of every 1 km grid cell
# of every MTUC polygon, epoch by epoch.
#
# Input   PATH_UCDB_MTUC, DIR_GHS_POP_MOLL
#         DIR_NTL_DMSP, DIR_NTL_VIIRS (product VIIRS_PRODUCT), DIR_POPULATION
# Output  PATHS$epoch_cells
#           city_id, year, grid_cell_id, nl_dmsp, nl_viirs, pop_gpw, pop_ghs
#
# THE GRID IS THE POPULATION GRID. The polygons of the R2024A database follow
# the GHS-POP 1 km Mollweide pixels, so that grid defines the cells (any part
# inside the polygon, as in step 2) and the other rasters are projected onto it:
#
#   nl_dmsp    DMSP, mean of the DMSP pixels in each cell.
#   nl_viirs   VIIRS VNL v2.1, mean of the VIIRS pixels in each cell (2015, 2020).
#   pop_gpw    GPW population count, area-weighted sum of the GPW pixels in each
#              cell, so that the population total is preserved (GPWv4 for
#              2000-2020, GPWv3 for 1995).
#   pop_ghs    GHS-POP population count of the cell itself.
#
# Every raster is cropped around each city before projecting; the crop of each
# city is one task, and epochs run in parallel.
# ==============================================================================

source(here::here("src", "R", "setup.R"))
source(here::here("src", "R", "rasters.R"))

library(dplyr)
library(sf)
library(terra)
library(arrow)
library(foreach)
library(doParallel)

require_input(PATH_UCDB_MTUC)

inputs <- Reduce(function(a, b) merge(a, b, by = "year", all = TRUE), list(
  setNames(resolve_ghs_pop_rasters(BENCHMARK_YEARS, mollweide = TRUE), c("year", "ghs")),
  setNames(resolve_rasters_by_year(DIR_NTL_DMSP, BENCHMARK_YEARS, label = "DMSP"), c("year", "dmsp")),
  setNames(resolve_viirs_rasters(VIIRS_YEARS), c("year", "viirs")),
  setNames(resolve_population_rasters(BENCHMARK_YEARS), c("year", "gpw"))))


# ------------------------------------------------------------------------------
# Extraction, one epoch per worker
# ------------------------------------------------------------------------------

cl <- start_cluster(min(N_CORES, nrow(inputs)))
on.exit(stop_cluster(cl), add = TRUE)

log_step(sprintf("Extracting lights and population on the 1 km grid for %d epochs.", nrow(inputs)))

cells <- foreach(
  k = seq_len(nrow(inputs)),
  .packages = c("sf", "terra", "dplyr"),
  .combine = "rbind",
  .export = c("smooth_crop", "gauss_1d", "VIIRS_SIGMA_KM")
) %dopar% {

  sf::sf_use_s2(FALSE)
  yr <- inputs$year[k]
  polys <- sf::st_read(PATH_UCDB_MTUC, layer = paste0("GHSL_UCDB_MTUC_", yr, "_GLOBE_R2024"), quiet = TRUE)
  polys <- sf::st_make_valid(polys[, "ID_UC_G0"])

  r_pop  <- terra::rast(inputs$ghs[k])
  names(r_pop) <- "pop_ghs"
  r_dmsp <- terra::rast(inputs$dmsp[k])
  r_gpw  <- terra::rast(inputs$gpw[k])
  do_viirs <- !is.na(inputs$viirs[k])
  r_viirs <- if (do_viirs) terra::rast(inputs$viirs[k]) else NULL

  polys_v <- terra::vect(polys)
  out <- dplyr::bind_rows(lapply(seq_len(nrow(polys_v)), function(i) {
    r_pop_c <- terra::crop(r_pop, polys_v[i], snap = "out")

    # Extent of the city in longitude/latitude, with a margin.
    e_ll <- terra::ext(terra::project(terra::as.polygons(terra::ext(r_pop_c), crs = terra::crs(r_pop)),
                                      terra::crs(r_dmsp)))
    e_ll <- terra::extend(e_ll, 0.02)

    # NA where the city falls outside the coverage of a raster (the DMSP and
    # VIIRS composites stop at 65S and 75N).
    na_layer <- function() terra::init(r_pop_c, NA)

    nl_dmsp <- tryCatch(terra::project(terra::crop(r_dmsp, e_ll, snap = "out"), r_pop_c, method = "average"),
                        error = function(e) na_layer())
    names(nl_dmsp) <- "nl_dmsp"

    pop_gpw <- tryCatch(terra::project(terra::crop(r_gpw, terra::extend(e_ll, 0.05), snap = "out"), r_pop_c, method = "sum"),
                        error = function(e) na_layer())
    names(pop_gpw) <- "pop_gpw"

    layers <- c(r_pop_c, nl_dmsp, pop_gpw)
    if (do_viirs) {
      nl_viirs <- tryCatch(terra::project(smooth_crop(r_viirs, e_ll, VIIRS_SIGMA_KM), r_pop_c, method = "average"),
                           error = function(e) na_layer())
      names(nl_viirs) <- "nl_viirs"
      layers <- c(layers, nl_viirs)
    }

    e <- terra::extract(layers, polys_v[i], xy = TRUE, exact = TRUE)
    e <- e[e$fraction > 0, ]
    e$city_id <- polys$ID_UC_G0[i]
    e
  }))

  if (!do_viirs) out$nl_viirs <- NA_real_
  out$grid_cell_id <- terra::cellFromXY(r_pop, cbind(out$x, out$y))
  out$year <- yr
  out[, c("city_id", "year", "grid_cell_id", "nl_dmsp", "nl_viirs", "pop_gpw", "pop_ghs")]
}

cells <- dplyr::arrange(cells, city_id, year, grid_cell_id)

log_step("Cells by epoch:")
print(cells |>
        dplyr::group_by(year) |>
        dplyr::summarise(cities = dplyr::n_distinct(city_id), cells = dplyr::n(),
                         pop_gpw_millions = round(sum(pop_gpw, na.rm = TRUE) / 1e6),
                         pop_ghs_millions = round(sum(pop_ghs, na.rm = TRUE) / 1e6)))

write_parquet(cells, prepare_output(PATHS$epoch_cells))
log_step("Wrote ", PATHS$epoch_cells)
