# ==============================================================================
# 01_build_capital_panel.R
#
# Case study 1, step 1. Flags which urban centres are national capitals and
# writes the analysis panel used by Table 4.
#
# Input   PATHS$dataset     (01_data_construction/06_consolidate_dataset.R)
#         PATH_CAPITALS     reference list of national capitals
# Output  <DIR_CLEAN>/case_studies/capital_panel.parquet
#
# MATCHING. The capital list identifies cities by name, so the join is on
# (country, city name) after transliterating to ASCII and lowercasing both
# sides. Without the transliteration, "Bogotá", "San José" and "Malé" fail to
# match their accented or unaccented counterparts depending on which spelling
# each source happens to use.
#
# TWO LIMITATIONS, both inherited from the design and both stated in the paper.
#
#   1. Capital status is time-invariant. A country that moved its capital during
#      1995-2020 is coded at its current capital throughout. The affected set is
#      small but non-empty, and it is a known simplification rather than an
#      oversight.
#
#   2. Name matching is not error-free. A capital whose UCDB name differs from
#      the reference list beyond accents is coded as a non-capital. The known
#      cases, and their effect on Table 4, are documented in the README of this
#      folder.
# ==============================================================================

source(here::here("src", "R", "setup.R"))

library(dplyr)
library(tidyr)
library(readr)
library(stringi)
library(arrow)

OUTPUT <- file.path(DIR_CLEAN, "case_studies", "capital_panel.parquet")

require_input(PATHS$dataset, "01_data_construction/06_consolidate_dataset.R")
require_input(PATH_CAPITALS)


# ------------------------------------------------------------------------------
# 1. Reference list of capitals
# ------------------------------------------------------------------------------

normalise <- function(x) tolower(stri_trans_general(x, "Latin-ASCII"))

capitals <- read_csv(PATH_CAPITALS, show_col_types = FALSE) |>
  transmute(
    country_name = normalise(CountryName),
    city_name    = normalise(CapitalName),
    capital      = 1L
  ) |>
  distinct(country_name, city_name, .keep_all = TRUE)


# ------------------------------------------------------------------------------
# 2. Join onto the dataset
# ------------------------------------------------------------------------------

dataset <- read_parquet(PATHS$dataset)

panel <- dataset |>
  select(
    country_name, iso_code, city_id, city_name, year,
    nl_gradient_no_pop_dmsp, nl_gradient_pop_dmsp,
    nl_gradient_no_pop_viirs, nl_gradient_pop_viirs,
    nl_gini_coef_dmsp, nl_theil_coef_dmsp,
    nl_gini_coef_viirs, nl_theil_coef_viirs
  ) |>
  mutate(
    country_key = normalise(country_name),
    city_key    = normalise(city_name)
  ) |>
  left_join(capitals, by = c("country_key" = "country_name", "city_key" = "city_name")) |>
  mutate(capital = coalesce(capital, 0L)) |>
  select(-country_key, -city_key)


# ------------------------------------------------------------------------------
# 3. Write
# ------------------------------------------------------------------------------

write_parquet(panel, prepare_output(OUTPUT))
log_step("Wrote ", OUTPUT)
