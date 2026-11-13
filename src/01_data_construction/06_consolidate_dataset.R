# ==============================================================================
# 06_consolidate_dataset.R
#
# Step 6 of 6. Assembles the Urban Inequality Dataset from the metric tables and
# the cell-level extractions, and writes its codebook.
#
# Input   PATHS$gradients_{pop,no_pop}_{dmsp,viirs}[_ghs]   (step 4)
#         PATHS$gradients_pwc_{pop,no_pop}_{dmsp,viirs}[_ghs]  (step 4b)
#         PATHS$gini_{dmsp,viirs}[_ghs], PATHS$theil_{dmsp,viirs}[_ghs]  (step 5)
#         PATHS$cells_dmsp                            (step 3)
#         PATHS$cells_viirs                           (step 3)
#         PATH_UCDB
# Output  PATHS$dataset    one row per city-year with at least one metric, 34 columns
#         PATHS$codebook
#
# NAMING. Every metric is computed twice, with GPW population counts (suffix
# _gpw, for instance nl_gini_coef_viirs_gpw) and with GHS-POP R2023A population
# counts (suffix _ghs). The population of each city-year is reported from both
# sources: total_pop_gpw and total_pop_ghs. The gradients are reported twice
# more, measured from the population-weighted centroid of each city-year
# (nl_gradient_pwc_*, step 4b) instead of a point on the polygon's surface.
#
# THE ROW UNIVERSE. A city-year is kept when at least one GPW metric could be
# computed for it; small cities that support a Gini but not a gradient stay in
# with the gradient left missing. The GHS-POP metrics and the gradients from
# population-weighted centroids are attached to those rows, so the universe
# does not depend on them.
#
# Identifiers come from the UCDB, keyed on city_id, and never from the metric
# tables. City name used to be carried only by the DMSP gradient table, so
# dropping rows with a missing name quietly re-imposed the DMSP gradient sample
# on the whole dataset and undid the full join.
# ==============================================================================

source(here::here("src", "R", "setup.R"))
source(here::here("src", "R", "sources.R"))

library(dplyr)
library(tidyr)
library(sf)
library(arrow)
library(readr)


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
  read_metric(PATHS$gradients_no_pop_dmsp,  "beta_1", "nl_gradient_no_pop_dmsp_gpw",  "04_estimate_gradients.R"),
  read_metric(PATHS$gradients_no_pop_viirs, "beta_1", "nl_gradient_no_pop_viirs_gpw", "04_estimate_gradients.R"),
  read_metric(PATHS$gradients_pop_dmsp,     "beta_1", "nl_gradient_pop_dmsp_gpw",     "04_estimate_gradients.R"),
  read_metric(PATHS$gradients_pop_viirs,    "beta_1", "nl_gradient_pop_viirs_gpw",    "04_estimate_gradients.R"),
  read_metric(PATHS$gini_dmsp,   "nl_gini_coef",  "nl_gini_coef_dmsp_gpw",   "05_compute_dispersion_indices.R"),
  read_metric(PATHS$gini_viirs,  "nl_gini_coef",  "nl_gini_coef_viirs_gpw",  "05_compute_dispersion_indices.R"),
  read_metric(PATHS$theil_dmsp,  "nl_theil_coef", "nl_theil_coef_dmsp_gpw",  "05_compute_dispersion_indices.R"),
  read_metric(PATHS$theil_viirs, "nl_theil_coef", "nl_theil_coef_viirs_gpw", "05_compute_dispersion_indices.R")
)

# A full join, so a city-year survives if any single metric could be computed.
dataset <- Reduce(function(a, b) dplyr::full_join(a, b, by = c("city_id", "year")), metrics) |>
  dplyr::mutate(city_id = as.integer(city_id), year = as.integer(year))

log_step(sprintf("Union of all metric tables: %s city-years.", format(nrow(dataset), big.mark = ",")))

# The same metrics with GHS-POP population, attached to the rows above.
metrics_ghs <- list(
  read_metric(PATHS$gradients_no_pop_dmsp_ghs,  "beta_1", "nl_gradient_no_pop_dmsp_ghs",  "04_estimate_gradients.R"),
  read_metric(PATHS$gradients_no_pop_viirs_ghs, "beta_1", "nl_gradient_no_pop_viirs_ghs", "04_estimate_gradients.R"),
  read_metric(PATHS$gradients_pop_dmsp_ghs,     "beta_1", "nl_gradient_pop_dmsp_ghs",     "04_estimate_gradients.R"),
  read_metric(PATHS$gradients_pop_viirs_ghs,    "beta_1", "nl_gradient_pop_viirs_ghs",    "04_estimate_gradients.R"),
  read_metric(PATHS$gini_dmsp_ghs,   "nl_gini_coef",  "nl_gini_coef_dmsp_ghs",   "05_compute_dispersion_indices.R"),
  read_metric(PATHS$gini_viirs_ghs,  "nl_gini_coef",  "nl_gini_coef_viirs_ghs",  "05_compute_dispersion_indices.R"),
  read_metric(PATHS$theil_dmsp_ghs,  "nl_theil_coef", "nl_theil_coef_dmsp_ghs",  "05_compute_dispersion_indices.R"),
  read_metric(PATHS$theil_viirs_ghs, "nl_theil_coef", "nl_theil_coef_viirs_ghs", "05_compute_dispersion_indices.R")
)
# Gradients measured from population-weighted centroids (step 4b).
metrics_pwc <- list(
  read_metric(PATHS$gradients_pwc_no_pop_dmsp,      "beta_1", "nl_gradient_pwc_no_pop_dmsp_gpw",  "04b_estimate_gradients_pwc.R"),
  read_metric(PATHS$gradients_pwc_no_pop_viirs,     "beta_1", "nl_gradient_pwc_no_pop_viirs_gpw", "04b_estimate_gradients_pwc.R"),
  read_metric(PATHS$gradients_pwc_pop_dmsp,         "beta_1", "nl_gradient_pwc_pop_dmsp_gpw",     "04b_estimate_gradients_pwc.R"),
  read_metric(PATHS$gradients_pwc_pop_viirs,        "beta_1", "nl_gradient_pwc_pop_viirs_gpw",    "04b_estimate_gradients_pwc.R"),
  read_metric(PATHS$gradients_pwc_no_pop_dmsp_ghs,  "beta_1", "nl_gradient_pwc_no_pop_dmsp_ghs",  "04b_estimate_gradients_pwc.R"),
  read_metric(PATHS$gradients_pwc_no_pop_viirs_ghs, "beta_1", "nl_gradient_pwc_no_pop_viirs_ghs", "04b_estimate_gradients_pwc.R"),
  read_metric(PATHS$gradients_pwc_pop_dmsp_ghs,     "beta_1", "nl_gradient_pwc_pop_dmsp_ghs",     "04b_estimate_gradients_pwc.R"),
  read_metric(PATHS$gradients_pwc_pop_viirs_ghs,    "beta_1", "nl_gradient_pwc_pop_viirs_ghs",    "04b_estimate_gradients_pwc.R")
)
for (m in c(metrics_ghs, metrics_pwc)) {
  dataset <- dplyr::left_join(
    dataset,
    dplyr::mutate(m, city_id = as.integer(city_id), year = as.integer(year)),
    by = c("city_id", "year")
  )
}


# ------------------------------------------------------------------------------
# 2. Identifiers from the UCDB
# ------------------------------------------------------------------------------

require_input(PATH_UCDB)

log_step("Attaching identifiers from the UCDB.")

urban_meta <- st_read(PATH_UCDB, quiet = TRUE) |>
  st_drop_geometry() |>
  dplyr::transmute(
    city_id      = as.integer(ID_HDC_G0),
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
    nl_sum_dmsp   = sum(nl_measure, na.rm = TRUE),
    total_pop_gpw = sum(pop, na.rm = TRUE),
    total_pop_ghs = sum(pop_ghs, na.rm = TRUE),
    n_cells       = dplyr::n_distinct(grid_cell_id),
    .groups = "drop"
  )

agg_viirs <- read_parquet(PATHS$cells_viirs) |>
  dplyr::group_by(city_id, year) |>
  dplyr::summarise(nl_sum_viirs = sum(nl_measure, na.rm = TRUE), .groups = "drop")

dataset <- dataset |>
  dplyr::left_join(dplyr::mutate(agg_dmsp, city_id = as.integer(city_id), year = as.integer(year)),
                   by = c("city_id", "year")) |>
  dplyr::left_join(dplyr::mutate(agg_viirs, city_id = as.integer(city_id), year = as.integer(year)),
                   by = c("city_id", "year"))


# ------------------------------------------------------------------------------
# 4. Column order
# ------------------------------------------------------------------------------

METRIC_COLS <- c(
  "nl_gradient_no_pop_dmsp_gpw", "nl_gradient_no_pop_viirs_gpw",
  "nl_gradient_pop_dmsp_gpw",    "nl_gradient_pop_viirs_gpw",
  "nl_gini_coef_dmsp_gpw",  "nl_gini_coef_viirs_gpw",
  "nl_theil_coef_dmsp_gpw", "nl_theil_coef_viirs_gpw"
)
METRIC_COLS_GHS <- sub("_gpw$", "_ghs", METRIC_COLS)
PWC_COLS <- c(
  "nl_gradient_pwc_no_pop_dmsp_gpw", "nl_gradient_pwc_no_pop_viirs_gpw",
  "nl_gradient_pwc_pop_dmsp_gpw",    "nl_gradient_pwc_pop_viirs_gpw"
)
PWC_COLS_GHS <- sub("_gpw$", "_ghs", PWC_COLS)

dataset <- dataset |>
  dplyr::select(
    country_name, iso_code, city_id, city_name, year,
    dplyr::all_of(METRIC_COLS), dplyr::all_of(METRIC_COLS_GHS),
    dplyr::all_of(PWC_COLS), dplyr::all_of(PWC_COLS_GHS),
    nl_sum_dmsp, nl_sum_viirs, total_pop_gpw, total_pop_ghs, n_cells
  ) |>
  dplyr::arrange(city_id, year)


# ------------------------------------------------------------------------------
# 5. Integrity checks
# ------------------------------------------------------------------------------

duplicates <- dataset |> dplyr::count(city_id, year) |> dplyr::filter(n > 1)
if (nrow(duplicates) > 0) {
  stop(nrow(duplicates), " duplicate (city_id, year) pairs after the join.", call. = FALSE)
}

stopifnot(
  !any(is.na(dataset$city_name)),
  !any(is.na(dataset$country_name)),
  !any(is.na(dataset$iso_code))
)

empty_rows <- rowSums(!is.na(dataset[METRIC_COLS])) == 0
if (any(empty_rows)) {
  stop(sum(empty_rows), " rows carry no metric at all.", call. = FALSE)
}

# VIIRS quantities exist only for 2015 and 2020.
viirs_cols <- c(grep("viirs", c(METRIC_COLS, METRIC_COLS_GHS, PWC_COLS, PWC_COLS_GHS), value = TRUE), "nl_sum_viirs")
stray_viirs <- dataset |>
  dplyr::filter(!year %in% VIIRS_YEARS) |>
  dplyr::summarise(dplyr::across(dplyr::all_of(viirs_cols), ~ sum(!is.na(.x)))) |>
  sum()
if (stray_viirs > 0) {
  stop(stray_viirs, " VIIRS values fall outside ",
       paste(VIIRS_YEARS, collapse = " and "), ".", call. = FALSE)
}


# ------------------------------------------------------------------------------
# 6. Codebook
# ------------------------------------------------------------------------------

describe_metric <- function(v) {
  measure <- dplyr::case_when(
    grepl("gradient_pwc_no_pop", v) ~ "Luminosity gradient without population control, measured from the population-weighted centroid of the city-year (slope of asinh(lights) on asinh(distance to the centroid))",
    grepl("gradient_pwc_pop", v)    ~ "Luminosity gradient with population control, measured from the population-weighted centroid of the city-year (slope of asinh(lights) on asinh(distance to the centroid), controlling for asinh(population)); centroid weighted by the same population source",
    grepl("gradient_no_pop", v) ~ "Luminosity gradient without population control (slope of asinh(lights) on asinh(distance to the city centre))",
    grepl("gradient_pop", v)    ~ "Luminosity gradient with population control (slope of asinh(lights) on asinh(distance to the city centre), controlling for asinh(population))",
    grepl("gini", v)            ~ "Population-weighted Gini coefficient of per-capita luminosity across grid cells",
    grepl("theil", v)           ~ "Population-weighted Theil index of per-capita luminosity across grid cells"
  )
  source <- ifelse(grepl("_dmsp", v), "DMSP lights (all years)", "VIIRS VNL v2.1 lights (2015, 2020)")
  population <- ifelse(grepl("_ghs$", v), "GHS-POP R2023A population counts", "GPW population counts")
  paste0(measure, "; ", source, "; ", population, "; GHS-UCDB R2019A polygon")
}

descriptions <- c(
  country_name  = "Country name (GHS-UCDB R2019A)",
  iso_code      = "ISO 3166-1 alpha-3 country code",
  city_id       = "Urban centre identifier (GHS-UCDB R2019A, ID_HDC_G0); the polygon is fixed over time",
  city_name     = "Urban centre name (GHS-UCDB R2019A)",
  year          = "Benchmark year (1995, 2000, 2005, 2010, 2015, 2020)",
  nl_sum_dmsp   = "Total DMSP lights (DN) summed over the polygon's grid cells",
  nl_sum_viirs  = "Total VIIRS VNL v2.1 radiance (nW/cm2/sr) summed over the polygon's grid cells (2015, 2020)",
  total_pop_gpw = "Total population: sum of GPW population counts over the polygon's grid cells (GPWv4 Rev. 11 for 2000-2020; GPWv3 UN-adjusted for 1995)",
  total_pop_ghs = "Total population: sum of GHS-POP R2023A population counts over the polygon's grid cells",
  n_cells       = "Number of 30 arc-second grid cells whose centres fall within the polygon"
)

codebook <- tibble::tibble(variable = names(dataset)) |>
  dplyr::mutate(
    description = dplyr::coalesce(unname(descriptions[variable]), describe_metric(variable)),
    type        = vapply(dataset[variable], function(z) class(z)[1], character(1)),
    non_missing = vapply(dataset[variable], function(z) sum(!is.na(z)), integer(1))
  ) |>
  add_source_columns(source_ids_main)   # inputs and licences (src/R/sources.R)


# ------------------------------------------------------------------------------
# 7. Write
# ------------------------------------------------------------------------------

write_parquet(dataset, prepare_output(PATHS$dataset))
readr::write_excel_csv(dataset, sub("\\.parquet$", ".csv", PATHS$dataset))
readr::write_csv(codebook, prepare_output(PATHS$codebook))
write_sources_table()

log_step(sprintf("%s rows, %s cities, %s countries.",
                 format(nrow(dataset), big.mark = ","),
                 format(dplyr::n_distinct(dataset$city_id), big.mark = ","),
                 format(dplyr::n_distinct(dataset$country_name), big.mark = ",")))
print(colSums(!is.na(dataset[c(METRIC_COLS, METRIC_COLS_GHS, PWC_COLS, PWC_COLS_GHS)])))
log_step("Wrote ", PATHS$dataset, " and ", PATHS$codebook)

log_step("Step 6 complete. The dataset is built.")
