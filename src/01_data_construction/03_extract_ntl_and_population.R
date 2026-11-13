# ==============================================================================
# 03_extract_ntl_and_population.R
#
# Step 3 of 6. Cell-level extraction. For each benchmark year and each NTL
# source, records the luminosity and population of every ~1 km grid cell whose
# centre falls inside an urban centre polygon.
#
# Input   PATH_UCDB
#         DIR_NTL_DMSP     one DMSP composite per benchmark year
#         DIR_NTL_VIIRS    VIIRS VNL v2.1 (product VIIRS_PRODUCT), 2015 and 2020
#         DIR_POPULATION   one population count raster per benchmark year (GPW)
#         DIR_GHS_POP      one GHS-POP count raster per benchmark year
# Output  PATHS$cells_dmsp, PATHS$cells_viirs
#           city_id, year, grid_cell_id, x, y, nl_measure, pop, pop_ghs
#
# THE ANALYSIS GRID. The cells are the 30 arc-second pixels of the DMSP
# composites (step 1). DMSP values are read directly on that grid. VIIRS VNL is
# distributed on a finer 15 arc-second grid, so its value for each cell is the
# area-weighted mean of the VIIRS pixels that overlap the cell. Both sources are
# therefore measured on exactly the same cells, which the check at the end of
# this script verifies.
#
# POPULATION. Population enters as counts (persons per cell), interpolated
# bilinearly at the centre of each cell. GPW is the population source of every
# metric; GHS-POP is extracted alongside it to report a second population total
# per city-year. In 1995 GPWv3 is a 2.5 arc-minute grid, so its interpolated
# count is rescaled to the 30 arc-second cell (see population_at_points() in
# src/R/rasters.R).
#
# BOTH SOURCES ARE PROCESSED IN ONE SCRIPT, DELIBERATELY. The population inputs
# are resolved once and reused for both sources. Running the two extractions
# from separate scripts invites them to pick up different population inputs,
# and nothing downstream would report an error.
# ==============================================================================

source(here::here("src", "R", "setup.R"))
source(here::here("src", "R", "rasters.R"))

library(dplyr)
library(sf)
library(terra)
library(arrow)
library(foreach)
library(doParallel)


# ------------------------------------------------------------------------------
# 1. Resolve inputs
# ------------------------------------------------------------------------------

require_input(PATH_UCDB)

log_step("Reading urban centre polygons.")
urban_centres <- st_read(PATH_UCDB, quiet = TRUE)

dmsp_files  <- resolve_rasters_by_year(DIR_NTL_DMSP, BENCHMARK_YEARS, label = "DMSP")
viirs_files <- resolve_viirs_rasters(VIIRS_YEARS)
gpw_files   <- resolve_population_rasters(BENCHMARK_YEARS)
ghs_files   <- resolve_ghs_pop_rasters(BENCHMARK_YEARS)

inputs <- Reduce(function(a, b) merge(a, b, by = "year", all = TRUE), list(
  setNames(dmsp_files, c("year", "dmsp")), setNames(viirs_files, c("year", "viirs")),
  setNames(gpw_files, c("year", "gpw")), setNames(ghs_files, c("year", "ghs"))))

log_step("Inputs resolved, one raster per benchmark year (DMSP | VIIRS | GPW | GHS-POP):")
for (i in seq_len(nrow(inputs))) {
  message(sprintf("    %d  %s | %s | %s | %s", inputs$year[i], basename(inputs$dmsp[i]),
                  if (is.na(inputs$viirs[i])) "-" else basename(inputs$viirs[i]),
                  basename(inputs$gpw[i]), basename(inputs$ghs[i])))
}


# ------------------------------------------------------------------------------
# 2. DMSP and population on the analysis grid
# ------------------------------------------------------------------------------

log_step(sprintf("Extracting DMSP and population for %d year(s).", nrow(inputs)))

cl <- start_cluster(min(N_CORES, nrow(inputs)))

cells_dmsp <- foreach(
  k = seq_len(nrow(inputs)),
  .packages = c("sf", "terra", "dplyr"),
  .combine = "rbind",
  .export = c("population_at_points", "values_in_polygons")
) %dopar% {

  r_ntl <- terra::rast(inputs$dmsp[k])

  # Pixels whose centre falls inside each polygon, with their global cell index.
  values <- values_in_polygons(r_ntl, urban_centres)
  names(values)[names(values) == "value"] <- "nl_measure"

  # values_in_polygons returns the row of each polygon; map it back to the UCDB id.
  values$city_id <- urban_centres$ID_HDC_G0[values$ID]

  xy <- cbind(values$x, values$y)
  values$pop     <- population_at_points(terra::rast(inputs$gpw[k]), xy, terra::res(r_ntl))
  values$pop_ghs <- population_at_points(terra::rast(inputs$ghs[k]), xy, terra::res(r_ntl))

  values |>
    dplyr::transmute(city_id, year = inputs$year[k], grid_cell_id = cell, x, y,
                     nl_measure, pop, pop_ghs)
}

stop_cluster(cl)

log_step(sprintf("DMSP: %s cell-year records.", format(nrow(cells_dmsp), big.mark = ",")))
write_parquet(cells_dmsp, prepare_output(PATHS$cells_dmsp))
log_step("Wrote ", PATHS$cells_dmsp)


# ------------------------------------------------------------------------------
# 3. VIIRS on the same cells
# ------------------------------------------------------------------------------

half <- terra::res(terra::rast(dmsp_files$path[1]))[1] / 2

cells_viirs <- cells_dmsp |>
  dplyr::filter(year %in% VIIRS_YEARS) |>
  dplyr::select(city_id, year, grid_cell_id, x, y, pop, pop_ghs)

# City-years are spread over the workers; each worker opens the rasters itself.
city_years <- dplyr::distinct(cells_viirs, year, city_id)
city_years$chunk <- (seq_len(nrow(city_years)) - 1) %% N_CORES
chunks <- cells_viirs |>
  dplyr::select(city_id, year, grid_cell_id, x, y) |>
  dplyr::inner_join(city_years, by = c("year", "city_id")) |>
  split(~ chunk)

log_step(sprintf("Extracting VIIRS for %s city-years.", format(nrow(city_years), big.mark = ",")))

cl <- start_cluster()

viirs_values <- foreach(
  d_chunk = chunks,
  .packages = c("terra"),
  .combine = "rbind",
  .export = c("smooth_crop", "gauss_1d", "area_mean_at_cells", "VIIRS_SIGMA_KM", "viirs_files", "half")
) %dopar% {

  rasters <- lapply(split(viirs_files$path, viirs_files$year), terra::rast)

  do.call(rbind, lapply(split(d_chunk, list(d_chunk$year, d_chunk$city_id), drop = TRUE), function(d) {
    r <- rasters[[as.character(d$year[1])]]
    e_ll <- terra::ext(min(d$x) - half, max(d$x) + half, min(d$y) - half, max(d$y) + half)
    v <- tryCatch(area_mean_at_cells(smooth_crop(r, e_ll, VIIRS_SIGMA_KM), d$x, d$y, half),
                  error = function(e) rep(NA_real_, nrow(d)))
    data.frame(city_id = d$city_id, year = d$year, grid_cell_id = d$grid_cell_id, nl_measure = v)
  }))
}

stop_cluster(cl)

cells_viirs <- cells_viirs |>
  dplyr::left_join(viirs_values, by = c("city_id", "year", "grid_cell_id")) |>
  dplyr::select(city_id, year, grid_cell_id, x, y, nl_measure, pop, pop_ghs)

log_step(sprintf("VIIRS: %s cell-year records.", format(nrow(cells_viirs), big.mark = ",")))
write_parquet(cells_viirs, prepare_output(PATHS$cells_viirs))
log_step("Wrote ", PATHS$cells_viirs)


# ------------------------------------------------------------------------------
# 4. Verify that the two sources share one grid
# ------------------------------------------------------------------------------
# Every metric in the paper is reported for both sources and compared directly,
# which only means anything if the two are measured on the same cells, with the
# same population.

log_step("Verifying that the DMSP and VIIRS extractions share a grid.")

overlap <- cells_dmsp |>
  dplyr::filter(year %in% VIIRS_YEARS) |>
  dplyr::select(city_id, year, grid_cell_id, x, y, pop) |>
  dplyr::inner_join(
    dplyr::select(cells_viirs, city_id, year, grid_cell_id, x, y, pop),
    by = c("city_id", "year", "grid_cell_id"),
    suffix = c("_dmsp", "_viirs")
  )

n_dmsp_overlap <- sum(cells_dmsp$year %in% VIIRS_YEARS)
if (nrow(overlap) != n_dmsp_overlap || nrow(overlap) != nrow(cells_viirs)) {
  stop("The DMSP and VIIRS extractions do not cover the same cells: ",
       nrow(overlap), " matched against ", n_dmsp_overlap, " (DMSP) and ",
       nrow(cells_viirs), " (VIIRS).", call. = FALSE)
}

max_coord_gap <- max(abs(overlap$x_dmsp - overlap$x_viirs), abs(overlap$y_dmsp - overlap$y_viirs))
pop_gap <- max(abs(overlap$pop_dmsp - overlap$pop_viirs), na.rm = TRUE)
if (max_coord_gap > 0 || pop_gap > 0) {
  stop("Matched cells differ between the two extractions (coordinates: ", max_coord_gap,
       "; population: ", signif(pop_gap, 4), ").", call. = FALSE)
}

log_step(sprintf("Grid check passed: %s cells identical in both sources.",
                 format(nrow(overlap), big.mark = ",")))

log_step("Step 3 complete.")
