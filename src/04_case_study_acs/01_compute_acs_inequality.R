# ==============================================================================
# 01_compute_acs_inequality.R
#
# Case study 2, step 1. Census-based inequality for US cities, from American
# Community Survey household microdata obtained through IPUMS USA.
#
# Input   DIR_ACS_IPUMS   one .xml DDI per ACS sample, with its .dat.gz alongside
# Output  PATHS$acs_gini, PATHS$acs_theil
#
# The Gini and the Theil are computed in one pass so that the two measures are
# always built from the same records, the same weights and the same set of
# samples.
#
# UNIT OF OBSERVATION. `distinct(SERIAL)` keeps one record per household. IPUMS
# microdata is person-level, so without this every household would be counted
# once per member and large households would be over-weighted.
#
# WEIGHTS. HHWT, the IPUMS household sampling weight. Unweighted city estimates
# would not be representative.
#
# EXCLUSIONS, matching the treatment of the luminosity measures:
#   both     the IPUMS missing code 9999999, and negative incomes
#   Theil    additionally zero incomes, since the index takes logarithms
# This is the census-side counterpart of dropping zero-luminosity cells from the
# Theil but keeping them in the Gini.
#
# A NOTE ON THE GINI ESTIMATOR. `unbiased = TRUE` applies the n/(n-1)
# small-sample correction, whereas the luminosity Gini in
# src/R/inequality.R uses `unbiased = FALSE`. The published results were
# produced this way and the setting is preserved here so that the repository
# reproduces the paper. The two differ by a factor of n/(n-1); on ACS city
# samples of thousands of households that is a fourth-decimal effect, far below
# the precision reported in Table 5. It is nonetheless an inconsistency with the
# paper's statement that the same functional forms are used on both sides, and
# is flagged here rather than silently reconciled.
# ==============================================================================

source(here::here("src", "R", "setup.R"))
source(here::here("src", "R", "inequality.R"))

library(dplyr)
library(purrr)
library(ipumsr)
library(DescTools)
library(writexl)

ACS_GINI_UNBIASED <- TRUE   # see the header note

ddi_files <- list.files(DIR_ACS_IPUMS, pattern = "\\.xml$", full.names = TRUE)
if (length(ddi_files) == 0) {
  stop("No IPUMS DDI (.xml) files found in ", DIR_ACS_IPUMS, call. = FALSE)
}
log_step(sprintf("Found %d ACS sample(s).", length(ddi_files)))


# ------------------------------------------------------------------------------
# Process one ACS sample
# ------------------------------------------------------------------------------

process_sample <- function(ddi_path) {
  log_step("Reading ", basename(ddi_path))

  ddi  <- read_ipums_ddi(ddi_path)
  data <- read_ipums_micro(ddi, verbose = FALSE)

  households <- data |>
    distinct(SERIAL, .keep_all = TRUE) |>
    mutate(
      CITY_NAME    = as_factor(CITY),
      STATEFIP     = as.factor(STATEFIP),
      HHINCOME_RAW = as.numeric(HHINCOME),

      # Kept for the Gini: missing code and negatives out, zeros in.
      income_gini = case_when(
        HHINCOME_RAW == 9999999 ~ NA_real_,
        HHINCOME_RAW < 0        ~ NA_real_,
        TRUE                    ~ HHINCOME_RAW
      ),

      # Kept for the Theil: zeros additionally out, for the logarithm.
      income_theil = case_when(
        HHINCOME_RAW == 9999999 ~ NA_real_,
        HHINCOME_RAW <= 0       ~ NA_real_,
        TRUE                    ~ HHINCOME_RAW
      )
    )

  households |>
    group_by(CITY_NAME, STATEFIP) |>
    summarise(
      year  = first(YEAR),
      gini  = DescTools::Gini(x = income_gini, weights = HHWT,
                              unbiased = ACS_GINI_UNBIASED, na.rm = TRUE),
      theil = theil_weighted(x = income_theil, w = HHWT),

      households_weighted = sum(HHWT, na.rm = TRUE),
      households_obs      = n(),
      n_missing_code      = sum(HHINCOME_RAW == 9999999, na.rm = TRUE),
      n_negative          = sum(HHINCOME_RAW < 0, na.rm = TRUE),
      n_zero              = sum(HHINCOME_RAW == 0, na.rm = TRUE),
      .groups = "drop"
    )
}

results <- map_dfr(ddi_files, process_sample) |> arrange(year, CITY_NAME)


# ------------------------------------------------------------------------------
# Sanity checks
# ------------------------------------------------------------------------------

# Theil T is non-negative by construction. A negative value would mean the
# estimator, not the data, is wrong.
stopifnot(all(results$theil >= 0, na.rm = TRUE))
stopifnot(all(results$gini >= 0 & results$gini <= 1, na.rm = TRUE))

log_step(sprintf("Computed inequality for %s city-year records across %d samples.",
                 format(nrow(results), big.mark = ","), length(ddi_files)))
print(summary(results[c("gini", "theil")]))


# ------------------------------------------------------------------------------
# Write
# ------------------------------------------------------------------------------
# Two files, matching the layout the matching step expects.

write_xlsx(
  results |> select(CITY_NAME, STATEFIP, year, gini,
                    households_weighted, households_obs, n_missing_code, n_negative),
  prepare_output(PATHS$acs_gini)
)
log_step("Wrote ", PATHS$acs_gini)

write_xlsx(
  results |> select(CITY_NAME, STATEFIP, year, theil,
                    households_weighted, households_obs, n_missing_code,
                    n_negative, n_zero),
  prepare_output(PATHS$acs_theil)
)
log_step("Wrote ", PATHS$acs_theil)
