# ==============================================================================
# 03_extract_ntl_and_population.R
#
# Step 3 of 6. Cell-level extraction. For each benchmark year and each NTL
# source, reads the luminosity and population value of every ~1 km grid cell
# whose centre falls inside an urban centre polygon.
#
# Input   PATH_UCDB
#         DIR_NTL_DMSP, DIR_NTL_VIIRS   one annual composite per benchmark year
#         DIR_POPULATION                one density raster per benchmark year
# Output  PATHS$cells_dmsp, PATHS$cells_viirs
#           nl_measure, pop_density, grid_cell_id, x, y, city_id, year
#
# BOTH SOURCES ARE PROCESSED IN ONE SCRIPT, DELIBERATELY.
#
# The population raster set is resolved once, before the loop, and reused for
# both sources. Running the two extractions from separate scripts invites them
# to pick up different population inputs — a different revision, a different
# variant, or simply a different subset of a folder — and nothing downstream
# would report an error. The result would be Gini, Theil and gradient values
# whose DMSP and VIIRS versions are not comparable, and a published total
# population that matches only one of them. Resolving the inputs once removes
# that possibility by construction.
#
# Population is resampled onto the NTL grid with bilinear interpolation, since
# density is a continuous surface. In 1995 the GPWv3 input is ~5 km, so 1995
# values are smoother than later years; this is inherent to the source and is
# documented in the codebook.
# ==============================================================================

source(here::here("src", "R", "setup.R"))

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

population_files <- resolve_population_rasters(BENCHMARK_YEARS)
log_step("Population rasters resolved, one per benchmark year:")
for (i in seq_len(nrow(population_files))) {
  message(sprintf("    %d  %s", population_files$year[i],
                  basename(population_files$path[i])))
}

sources <- list(
  dmsp = list(
    dir    = DIR_NTL_DMSP,
    years  = BENCHMARK_YEARS,
    output = PATHS$cells_dmsp,
    label  = "extended DMSP-like"
  ),
  viirs = list(
    dir    = DIR_NTL_VIIRS,
    years  = VIIRS_YEARS,
    output = PATHS$cells_viirs,
    label  = "VIIRS VNL v2.1"
  )
)


# ------------------------------------------------------------------------------
# 2. Extraction
# ------------------------------------------------------------------------------

extract_source <- function(spec) {

  ntl_files <- resolve_rasters_by_year(spec$dir, spec$years, label = spec$label)

  jobs <- ntl_files |>
    dplyr::rename(path_ntl = path) |>
    dplyr::inner_join(
      dplyr::rename(population_files, path_pop = path),
      by = "year"
    )

  stopifnot(nrow(jobs) == length(spec$years))

  log_step(sprintf("Extracting %s for %d year(s).", spec$label, nrow(jobs)))

  cl <- start_cluster()
  on.exit(stop_cluster(cl), add = TRUE)

  cells <- foreach(
    k = seq_len(nrow(jobs)),
    .packages = c("sf", "terra", "dplyr"),
    .combine = "rbind"
  ) %dopar% {

    year_k <- jobs$year[k]

    r_ntl <- terra::rast(jobs$path_ntl[k])
    r_pop <- terra::rast(jobs$path_pop[k])

    # Population density is continuous, so bilinear rather than nearest
    # neighbour. The NTL raster is the target, which fixes the analysis grid.
    r_pop <- terra::resample(r_pop, r_ntl, method = "bilinear")

    stack <- c(r_ntl, r_pop)
    names(stack) <- c("nl_measure", "pop_density")

    # One call for all polygons is far faster than looping over cities.
    # cells = TRUE returns the global cell index, xy = TRUE the coordinates.
    values <- terra::extract(stack, terra::vect(urban_centres),
                             xy = TRUE, cells = TRUE)
    values <- as.data.frame(values)

    # terra returns a sequential polygon index; map it back to the UCDB id.
    values$city_id <- urban_centres$ID_HDC_G0[values$ID]

    values |>
      dplyr::select(-ID) |>
      dplyr::rename(grid_cell_id = cell) |>
      dplyr::mutate(year = year_k)
  }

  log_step(sprintf("%s: %s cell-year records.", spec$label,
                   format(nrow(cells), big.mark = ",")))

  write_parquet(cells, prepare_output(spec$output))
  log_step("Wrote ", spec$output)

  cells
}

extracted <- lapply(sources, extract_source)


# ------------------------------------------------------------------------------
# 3. Verify that the two sources share one grid
# ------------------------------------------------------------------------------
# Every metric in the paper is reported for both sources and compared directly,
# which only means anything if the two are measured on the same cells. This
# check makes that assumption explicit and fails loudly if it ever stops
# holding — for instance if a provider reissues a composite on a new grid.

log_step("Verifying that the DMSP and VIIRS extractions share a grid.")

overlap <- extracted$dmsp |>
  dplyr::filter(year %in% VIIRS_YEARS) |>
  dplyr::select(city_id, year, grid_cell_id, x, y, pop_density) |>
  dplyr::inner_join(
    extracted$viirs |>
      dplyr::select(city_id, year, grid_cell_id, x, y, pop_density),
    by = c("city_id", "year", "grid_cell_id"),
    suffix = c("_dmsp", "_viirs")
  )

n_dmsp_overlap <- sum(extracted$dmsp$year %in% VIIRS_YEARS)

if (nrow(overlap) != n_dmsp_overlap || nrow(overlap) != nrow(extracted$viirs)) {
  stop("The DMSP and VIIRS extractions do not cover the same cells: ",
       nrow(overlap), " matched against ", n_dmsp_overlap, " (DMSP) and ",
       nrow(extracted$viirs), " (VIIRS).", call. = FALSE)
}

max_coord_gap <- max(abs(overlap$x_dmsp - overlap$x_viirs),
                     abs(overlap$y_dmsp - overlap$y_viirs))
if (max_coord_gap > 0) {
  stop("Matched cells sit at different coordinates in the two sources ",
       "(max gap ", max_coord_gap, " degrees).", call. = FALSE)
}

pop_gap <- max(abs(overlap$pop_density_dmsp - overlap$pop_density_viirs), na.rm = TRUE)
if (pop_gap > 0) {
  stop("The same cell carries different population values in the two ",
       "extractions (max gap ", signif(pop_gap, 4), "). The two branches were ",
       "built on different population rasters; check DIR_POPULATION.",
       call. = FALSE)
}

log_step(sprintf("Grid check passed: %s cells identical in both sources.",
                 format(nrow(overlap), big.mark = ",")))

log_step("Step 3 complete.")
