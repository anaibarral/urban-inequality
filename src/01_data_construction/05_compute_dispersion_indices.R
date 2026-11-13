# ==============================================================================
# 05_compute_dispersion_indices.R
#
# Step 5 of 6. City-level Gini coefficients and Theil indices of per-capita
# luminosity, for both NTL sources.
#
# Both indices are computed over the distribution of NL_g / POP_g across the
# grid cells of a city, weighted by cell population, so that they describe
# inequality as experienced by residents rather than across equal-area units.
# The estimators live in src/R/inequality.R.
#
# Input   PATHS$cells_dmsp, PATHS$cells_viirs   (step 3)
# Output  PATHS$gini_{dmsp,viirs},  PATHS$theil_{dmsp,viirs}       (GPW population)
#         PATHS$gini_{dmsp,viirs}_ghs, PATHS$theil_{dmsp,viirs}_ghs (GHS-POP population)
#
# The two indices admit different cells, and that is why the Theil covers fewer
# city-years than the Gini in the published dataset:
#
#   Gini   needs POP_g > 0. Unlit but populated cells stay in and pull the
#          index up, which is the intended behaviour.
#   Theil  needs POP_g > 0 and NL_g > 0, because the index takes logarithms.
#          It therefore measures inequality among lit, populated cells only.
#
# Both require at least two admissible cells.
# ==============================================================================

source(here::here("src", "R", "setup.R"))
source(here::here("src", "R", "inequality.R"))

library(dplyr)
library(tidyr)
library(DescTools)
library(arrow)


# ------------------------------------------------------------------------------
# 1. Inputs
# ------------------------------------------------------------------------------

require_input(PATHS$cells_dmsp, "03_extract_ntl_and_population.R")
require_input(PATHS$cells_viirs, "03_extract_ntl_and_population.R")

# Each index is computed with GPW population counts (column pop) and with
# GHS-POP population counts (column pop_ghs), which serve both as the
# denominator of per-capita luminosity and as the weights.
jobs <- list(
  list(source = "dmsp",  cells = PATHS$cells_dmsp,  pop = "gpw",
       gini = PATHS$gini_dmsp,  theil = PATHS$theil_dmsp),
  list(source = "viirs", cells = PATHS$cells_viirs, pop = "gpw",
       gini = PATHS$gini_viirs, theil = PATHS$theil_viirs),
  list(source = "dmsp",  cells = PATHS$cells_dmsp,  pop = "ghs",
       gini = PATHS$gini_dmsp_ghs,  theil = PATHS$theil_dmsp_ghs),
  list(source = "viirs", cells = PATHS$cells_viirs, pop = "ghs",
       gini = PATHS$gini_viirs_ghs, theil = PATHS$theil_viirs_ghs)
)


# ------------------------------------------------------------------------------
# 2. Compute
# ------------------------------------------------------------------------------

for (job in jobs) {

  log_step(sprintf("=== %s dispersion indices, %s population ===",
                   toupper(job$source), toupper(job$pop)))

  cells <- read_parquet(job$cells)
  if (job$pop == "ghs") cells <- dplyr::mutate(cells, pop = pop_ghs)

  # --- Gini ---
  gini <- compute_dispersion_index(cells, index = "gini")

  # The Gini is bounded in [0, 1] by construction. In near-perfectly equal
  # cities floating point returns values of order -1e-33; those are numerical
  # zeros. Anything materially outside the unit interval is a real problem.
  stopifnot(all(gini$nl_gini_coef > -1e-8), all(gini$nl_gini_coef <= 1))
  gini <- dplyr::mutate(gini, nl_gini_coef = pmax(nl_gini_coef, 0))

  log_step(sprintf("Gini: %s city-years, median %.4f.",
                   format(nrow(gini), big.mark = ","), median(gini$nl_gini_coef)))
  write_parquet(gini, prepare_output(job$gini))
  log_step("Wrote ", job$gini)

  # --- Theil ---
  theil <- compute_dispersion_index(cells, index = "theil")

  # Theil T is non-negative in theory; `theil_weighted()` already truncates
  # numerical zeros. A negative value here would mean the estimator is wrong.
  stopifnot(all(theil$nl_theil_coef >= 0))

  log_step(sprintf("Theil: %s city-years, median %.4f.",
                   format(nrow(theil), big.mark = ","), median(theil$nl_theil_coef)))
  write_parquet(theil, prepare_output(job$theil))
  log_step("Wrote ", job$theil)

  # The admissibility rules imply a hierarchy: every city-year with a Theil
  # must have a Gini, since the Theil's cell filter is strictly tighter.
  # Verified here rather than discovered later in the quality checks.
  orphan_theil <- dplyr::anti_join(theil, gini, by = c("city_id", "year"))
  if (nrow(orphan_theil) > 0) {
    stop(nrow(orphan_theil), " city-years have a Theil but no Gini, which the ",
         "cell filters make impossible.", call. = FALSE)
  }

  rm(cells, gini, theil)
  gc()
}

log_step("Step 5 complete.")
