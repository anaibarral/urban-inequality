# ==============================================================================
# 04_estimate_gradients.R
#
# Step 4 of 6. City-level centre-periphery luminosity gradients.
#
# Estimates the four gradient columns of the published dataset: two
# specifications (with and without a population control) for each of the two
# NTL sources. The estimator itself lives in src/R/inequality.R and is shared,
# so the four columns differ only in their inputs.
#
#     asinh(NL_g) = alpha + beta * asinh(d_gc) [ + gamma * asinh(POP_g) ] + e_g
#
# beta is the reported gradient.
#
# Input   PATHS$cells_dmsp, PATHS$cells_viirs   (step 3)
#         PATHS$distances                       (step 2)
# Output  PATHS$gradients_{pop,no_pop}_{dmsp,viirs}       (GPW population)
#         PATHS$gradients_{pop,no_pop}_{dmsp,viirs}_ghs   (GHS-POP population)
#
# One regression is run per city-year, so this is the longest step in the
# pipeline: roughly 66,000 fits for DMSP and 22,000 for VIIRS per specification.
# ==============================================================================

source(here::here("src", "R", "setup.R"))
source(here::here("src", "R", "inequality.R"))

library(dplyr)
library(tidyr)
library(fixest)
library(arrow)
library(foreach)
library(doParallel)


# ------------------------------------------------------------------------------
# 1. Inputs
# ------------------------------------------------------------------------------

require_input(PATHS$distances, "02_compute_grid_distances.R")
require_input(PATHS$cells_dmsp, "03_extract_ntl_and_population.R")
require_input(PATHS$cells_viirs, "03_extract_ntl_and_population.R")

log_step("Reading grid-centroid distances.")
distances <- read_parquet(PATHS$distances)


# ------------------------------------------------------------------------------
# 2. Estimate
# ------------------------------------------------------------------------------

# Each specification is estimated twice: with GPW population counts (column
# pop) and with GHS-POP population counts (column pop_ghs). The population
# enters both the cell filter (pop > 0) and, with the control, the regression.
specifications <- list(
  list(source = "dmsp",  cells = PATHS$cells_dmsp,  control = TRUE,  pop = "gpw",
       output = PATHS$gradients_pop_dmsp),
  list(source = "dmsp",  cells = PATHS$cells_dmsp,  control = FALSE, pop = "gpw",
       output = PATHS$gradients_no_pop_dmsp),
  list(source = "viirs", cells = PATHS$cells_viirs, control = TRUE,  pop = "gpw",
       output = PATHS$gradients_pop_viirs),
  list(source = "viirs", cells = PATHS$cells_viirs, control = FALSE, pop = "gpw",
       output = PATHS$gradients_no_pop_viirs),
  list(source = "dmsp",  cells = PATHS$cells_dmsp,  control = TRUE,  pop = "ghs",
       output = PATHS$gradients_pop_dmsp_ghs),
  list(source = "dmsp",  cells = PATHS$cells_dmsp,  control = FALSE, pop = "ghs",
       output = PATHS$gradients_no_pop_dmsp_ghs),
  list(source = "viirs", cells = PATHS$cells_viirs, control = TRUE,  pop = "ghs",
       output = PATHS$gradients_pop_viirs_ghs),
  list(source = "viirs", cells = PATHS$cells_viirs, control = FALSE, pop = "ghs",
       output = PATHS$gradients_no_pop_viirs_ghs)
)

cl <- start_cluster()
on.exit(stop_cluster(cl), add = TRUE)

for (spec in specifications) {

  log_step(sprintf("=== %s gradients, %s population control, %s population ===",
                   toupper(spec$source), if (spec$control) "with" else "without",
                   toupper(spec$pop)))

  cells <- read_parquet(spec$cells) |>
    dplyr::left_join(distances, by = c("city_id", "grid_cell_id"))
  if (spec$pop == "ghs") cells <- dplyr::mutate(cells, pop = pop_ghs)

  gradients <- compute_gradients(cells, population_control = spec$control)

  log_step(sprintf("Estimated %s city-year gradients.",
                   format(nrow(gradients), big.mark = ",")))
  log_step(sprintf("Share negative: %.1f%%.",
                   100 * mean(gradients$beta_1 < 0)))

  write_parquet(gradients, prepare_output(spec$output))
  log_step("Wrote ", spec$output)

  rm(cells, gradients)
  gc()
}

log_step("Step 4 complete.")
