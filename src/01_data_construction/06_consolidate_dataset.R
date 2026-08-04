# ==============================================================================
# 06_consolidate_dataset.R
#
# Step 6 of 6. Assembles the published Urban Inequality Dataset from the metric
# tables and the cell-level extractions.
#
# Input   PATHS$gradients_{pop,no_pop}_{dmsp,viirs}   (step 4)
#         PATHS$gini_{dmsp,viirs}, PATHS$theil_{dmsp,viirs}  (step 5)
#         PATHS$cells_dmsp, PATHS$cells_viirs         (step 3)
#         PATH_UCDB
# Output  PATHS$dataset   70,024 city-year rows, 17 columns
#
# TWO DESIGN DECISIONS DETERMINE WHAT ENDS UP IN THE FILE.
#
# 1. Identifiers come from the UCDB, keyed on city_id, and never from the metric
#    tables. City name used to be carried only by the DMSP gradient table, so
#    dropping rows with a missing name quietly re-imposed the DMSP gradient
#    sample on the whole dataset and undid the full join.
#
# 2. The row universe is set by `UNIVERSE` below. "any" keeps a city-year when
#    at least one metric could be computed, which is what the published file
#    contains; small cities that support a Gini but not a gradient stay in with
#    the gradient left missing. "gradient" restricts to city-years with an
#    estimable DMSP gradient and reproduces the narrower 65,704-row extract.
# ==============================================================================

source(here::here("src", "R", "setup.R"))

library(dplyr)
library(tidyr)
library(sf)
library(arrow)

UNIVERSE <- "any"   # "any" (published dataset) or "gradient"

stopifnot(UNIVERSE %in% c("any", "gradient"))


# ------------------------------------------------------------------------------
# 1. Metric tables
# ------------------------------------------------------------------------------
# Each table contributes only its key and its own metric, with missing values
# dropped, so that no city-year enters the join without real information.

read_metric <- function(path, from, to, produced_by) {
  require_input(path, produced_by)
  read_parquet(path) |>
    dplyr::select(city_id, year, !!to := !!rlang::sym(from)) |>
    tidyr::drop_na(!!rlang::sym(to))
}

log_step("Reading metric tables.")

metrics <- list(
  read_metric(PATHS$gradients_no_pop_dmsp,  "beta_1", "nl_gradient_no_pop_dmsp",  "04_estimate_gradients.R"),
  read_metric(PATHS$gradients_no_pop_viirs, "beta_1", "nl_gradient_no_pop_viirs", "04_estimate_gradients.R"),
  read_metric(PATHS$gradients_pop_dmsp,     "beta_1", "nl_gradient_pop_dmsp",     "04_estimate_gradients.R"),
  read_metric(PATHS$gradients_pop_viirs,    "beta_1", "nl_gradient_pop_viirs",    "04_estimate_gradients.R"),
  read_metric(PATHS$gini_dmsp,   "nl_gini_coef",  "nl_gini_coef_dmsp",   "05_compute_dispersion_indices.R"),
  read_metric(PATHS$gini_viirs,  "nl_gini_coef",  "nl_gini_coef_viirs",  "05_compute_dispersion_indices.R"),
  read_metric(PATHS$theil_dmsp,  "nl_theil_coef", "nl_theil_coef_dmsp",  "05_compute_dispersion_indices.R"),
  read_metric(PATHS$theil_viirs, "nl_theil_coef", "nl_theil_coef_viirs", "05_compute_dispersion_indices.R")
)

# A full join, so a city-year survives if any single source produced a metric.
dataset <- Reduce(function(a, b) dplyr::full_join(a, b, by = c("city_id", "year")), metrics)

log_step(sprintf("Union of all metric tables: %s city-years.",
                 format(nrow(dataset), big.mark = ",")))

if (UNIVERSE == "gradient") {
  # Filter on the metric itself, never on a joined-in label.
  dataset <- tidyr::drop_na(dataset, nl_gradient_no_pop_dmsp)
  log_step(sprintf("Restricted to estimable DMSP gradients: %s city-years.",
                   format(nrow(dataset), big.mark = ",")))
}


# ------------------------------------------------------------------------------
# 2. Identifiers from the UCDB
# ------------------------------------------------------------------------------

require_input(PATH_UCDB)

log_step("Attaching identifiers from the UCDB.")

urban_meta <- st_read(PATH_UCDB, quiet = TRUE) |>
  st_drop_geometry() |>
  dplyr::select(
    city_id      = ID_HDC_G0,
    city_name    = UC_NM_MN,
    country_name = CTR_MN_NM,
    iso_code     = CTR_MN_ISO
  )

dataset <- dplyr::left_join(dataset, urban_meta, by = "city_id")


# ------------------------------------------------------------------------------
# 3. City-level aggregates
# ------------------------------------------------------------------------------
# Totals over the cells of each city-year. These contextualise the metrics and
# let users recover per-cell averages.

log_step("Aggregating cell-level totals.")

agg_dmsp <- read_parquet(PATHS$cells_dmsp) |>
  dplyr::group_by(city_id, year) |>
  dplyr::summarise(
    nl_sum_dmsp = sum(nl_measure, na.rm = TRUE),
    total_pop   = sum(pop_density, na.rm = TRUE),
    n_cells     = dplyr::n_distinct(grid_cell_id),
    .groups = "drop"
  )

agg_viirs <- read_parquet(PATHS$cells_viirs) |>
  dplyr::group_by(city_id, year) |>
  dplyr::summarise(nl_sum_viirs = sum(nl_measure, na.rm = TRUE), .groups = "drop")

dataset <- dataset |>
  dplyr::left_join(agg_dmsp,  by = c("city_id", "year")) |>
  dplyr::left_join(agg_viirs, by = c("city_id", "year"))


# ------------------------------------------------------------------------------
# 4. Column order
# ------------------------------------------------------------------------------

dataset <- dataset |>
  dplyr::select(
    country_name, iso_code, city_id, city_name, year,
    nl_gradient_no_pop_dmsp, nl_gradient_no_pop_viirs,
    nl_gradient_pop_dmsp,    nl_gradient_pop_viirs,
    nl_gini_coef_dmsp,  nl_gini_coef_viirs,
    nl_theil_coef_dmsp, nl_theil_coef_viirs,
    nl_sum_dmsp, nl_sum_viirs, total_pop, n_cells
  ) |>
  dplyr::arrange(city_id, year)


# ------------------------------------------------------------------------------
# 5. Integrity checks
# ------------------------------------------------------------------------------

METRIC_COLS <- c(
  "nl_gradient_no_pop_dmsp", "nl_gradient_no_pop_viirs",
  "nl_gradient_pop_dmsp",    "nl_gradient_pop_viirs",
  "nl_gini_coef_dmsp",  "nl_gini_coef_viirs",
  "nl_theil_coef_dmsp", "nl_theil_coef_viirs"
)

# No duplicate keys.
duplicates <- dataset |> dplyr::count(city_id, year) |> dplyr::filter(n > 1)
if (nrow(duplicates) > 0) {
  stop(nrow(duplicates), " duplicate (city_id, year) pairs after the join.",
       call. = FALSE)
}

# Identifiers complete for every row.
stopifnot(
  !any(is.na(dataset$city_name)),
  !any(is.na(dataset$country_name)),
  !any(is.na(dataset$iso_code))
)

# No empty rows: every row carries at least one metric by construction.
empty_rows <- rowSums(!is.na(dataset[METRIC_COLS])) == 0
if (any(empty_rows)) {
  stop(sum(empty_rows), " rows carry no metric at all.", call. = FALSE)
}

# VIIRS quantities exist only for 2015 and 2020.
viirs_cols <- c(grep("viirs", METRIC_COLS, value = TRUE), "nl_sum_viirs")
stray_viirs <- dataset |>
  dplyr::filter(!year %in% VIIRS_YEARS) |>
  dplyr::summarise(dplyr::across(dplyr::all_of(viirs_cols), ~ sum(!is.na(.x)))) |>
  sum()
if (stray_viirs > 0) {
  stop(stray_viirs, " VIIRS values fall outside ",
       paste(VIIRS_YEARS, collapse = " and "), ".", call. = FALSE)
}


# ------------------------------------------------------------------------------
# 6. Write
# ------------------------------------------------------------------------------

write_parquet(dataset, prepare_output(PATHS$dataset))

log_step(sprintf("Universe '%s': %s rows, %s cities, %s countries.",
                 UNIVERSE,
                 format(nrow(dataset), big.mark = ","),
                 format(dplyr::n_distinct(dataset$city_id), big.mark = ","),
                 format(dplyr::n_distinct(dataset$country_name), big.mark = ",")))
print(colSums(!is.na(dataset[METRIC_COLS])))
log_step("Wrote ", PATHS$dataset)

log_step("Step 6 complete. The dataset is built.")
