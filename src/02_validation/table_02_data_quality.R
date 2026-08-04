# ==============================================================================
# table_02_data_quality.R
#
# Reproduces TABLE 2 of the paper, "Data quality summary statistics", and every
# figure quoted in the Technical Validation subsections "Integrity and
# Completeness", "Variable Completeness" and "Geographic and Temporal Coverage".
#
# Input   PATHS$dataset   (01_data_construction/06_consolidate_dataset.R)
#         PATH_UCDB       to count urban centres absent from the dataset
# Output  outputs/tables/table_02_data_quality.csv
#         outputs/tables/table_02_panel_attrition.csv
#
# Every block prints the quantity together with the sentence of the paper it
# supports, so the manuscript can be checked against the output line by line.
#
# THE DENOMINATOR RULE. DMSP metrics and the city-level aggregates are
# summarised over all city-year observations. VIIRS metrics and nl_sum_viirs are
# summarised over the 2015 and 2020 observations only. Dividing a VIIRS count by
# the full panel would report the years the sensor does not cover as missing
# data rather than as out of scope, and would understate VIIRS completeness by
# roughly two thirds.
# ==============================================================================

source(here::here("src", "R", "setup.R"))
source(here::here("src", "R", "plotting.R"))

library(dplyr)
library(tidyr)
library(sf)
library(arrow)
library(readr)

require_input(PATHS$dataset, "01_data_construction/06_consolidate_dataset.R")

dataset <- read_parquet(PATHS$dataset)

GRADIENT_COLS <- c("nl_gradient_no_pop_dmsp", "nl_gradient_pop_dmsp",
                   "nl_gradient_no_pop_viirs", "nl_gradient_pop_viirs")
DMSP_METRICS  <- c("nl_gradient_no_pop_dmsp", "nl_gradient_pop_dmsp",
                   "nl_gini_coef_dmsp", "nl_theil_coef_dmsp")
VIIRS_METRICS <- c("nl_gradient_no_pop_viirs", "nl_gradient_pop_viirs",
                   "nl_gini_coef_viirs", "nl_theil_coef_viirs")
METRIC_COLS   <- c(DMSP_METRICS, VIIRS_METRICS)

n_obs       <- nrow(dataset)
n_cities    <- n_distinct(dataset$city_id)
n_countries <- n_distinct(dataset$country_name)
dataset_viirs <- filter(dataset, year %in% VIIRS_YEARS)
n_viirs     <- nrow(dataset_viirs)


# ------------------------------------------------------------------------------
# 0. Structural sanity
# ------------------------------------------------------------------------------

cat("\n=== 0. STRUCTURE ===\n")
cat(sprintf("Rows: %s | Columns: %d\n", format(n_obs, big.mark = ","), ncol(dataset)))

duplicates <- dataset |> count(city_id, year) |> filter(n > 1)
cat(sprintf("Duplicate city-year observations [paper: 'No duplicate city-year observations']: %d\n",
            nrow(duplicates)))

empty <- sum(rowSums(!is.na(dataset[METRIC_COLS])) == 0)
cat(sprintf("Rows with no metric at all (must be 0): %d\n", empty))

cat(sprintf("Missing identifiers (must be 0): city_name = %d | country_name = %d | iso_code = %d\n",
            sum(is.na(dataset$city_name)), sum(is.na(dataset$country_name)),
            sum(is.na(dataset$iso_code))))


# ------------------------------------------------------------------------------
# 1. Panel dimensions
# ------------------------------------------------------------------------------

cat("\n=== 1. PANEL DIMENSIONS ===\n")
cat(sprintf("City-year observations: %s\n", format(n_obs, big.mark = ",")))
cat(sprintf("Unique cities: %s\n", format(n_cities, big.mark = ",")))
cat(sprintf("Countries: %d\n", n_countries))

require_input(PATH_UCDB)
ucdb_ids <- st_read(PATH_UCDB, quiet = TRUE) |> st_drop_geometry() |> pull(ID_HDC_G0)
n_absent <- length(setdiff(unique(ucdb_ids), unique(dataset$city_id)))

cat(sprintf("Urban centres in the UCDB: %s\n",
            format(length(unique(ucdb_ids)), big.mark = ",")))
cat(sprintf("Absent from the dataset [paper: '820 never yield an estimable metric']: %d\n",
            n_absent))

countries_by_year <- dataset |> group_by(year) |> summarise(n = n_distinct(country_name))
cat("Countries present per year [paper: 'All 182 countries ... in every benchmark year']:\n")
print(as.data.frame(countries_by_year), row.names = FALSE)


# ------------------------------------------------------------------------------
# 2. Panel balance
# ------------------------------------------------------------------------------

cat("\n=== 2. PANEL BALANCE ===\n")
balanced_n <- n_cities * length(BENCHMARK_YEARS)
years_per_city <- dataset |> group_by(city_id) |> summarise(n_years = n_distinct(year))
n_complete   <- sum(years_per_city$n_years == length(BENCHMARK_YEARS))
n_incomplete <- n_cities - n_complete

cat(sprintf("Theoretical balanced panel (cities x %d): %s\n",
            length(BENCHMARK_YEARS), format(balanced_n, big.mark = ",")))
cat(sprintf("Panel completeness [Table 2]: %.1f%%\n", 100 * n_obs / balanced_n))
cat(sprintf("Cities with a complete panel: %s (%.1f%%)\n",
            format(n_complete, big.mark = ","), 100 * n_complete / n_cities))
cat(sprintf("Cities with an incomplete panel: %s (%.1f%%)\n",
            format(n_incomplete, big.mark = ","), 100 * n_incomplete / n_cities))
cat(sprintf("Cities missing exactly one year: %d\n", sum(years_per_city$n_years == 5)))
cat(sprintf("Cities present in a single year: %d\n", sum(years_per_city$n_years == 1)))


# ------------------------------------------------------------------------------
# 3. Attrition by year
# ------------------------------------------------------------------------------
# Polygons are fixed at their 2015 definition, so a city absent in a given year
# is not a city that had not yet been founded. It is a city whose cells record
# too little luminosity that year to support any metric. Absences concentrate in
# the early years, consistent with the global expansion of electrification.

cat("\n=== 3. ATTRITION BY YEAR ===\n")
attrition <- dataset |>
  group_by(year) |>
  summarise(cities_present = n_distinct(city_id), .groups = "drop") |>
  mutate(cities_absent = n_cities - cities_present)
print(as.data.frame(attrition), row.names = FALSE)


# ------------------------------------------------------------------------------
# 4. Incomplete panels by country
# ------------------------------------------------------------------------------

cat("\n=== 4. INCOMPLETE PANELS BY COUNTRY ===\n")
incomplete_ids <- years_per_city |>
  filter(n_years < length(BENCHMARK_YEARS)) |>
  pull(city_id)

by_country <- dataset |>
  filter(city_id %in% incomplete_ids) |>
  distinct(city_id, country_name) |>
  count(country_name, sort = TRUE)

print(head(as.data.frame(by_country), 6), row.names = FALSE)
cat(sprintf("Top 5 as a share of all incomplete cities [paper: 59.6%%]: %.1f%%\n",
            100 * sum(head(by_country$n, 5)) / length(incomplete_ids)))


# ------------------------------------------------------------------------------
# 5. Geographic coverage
# ------------------------------------------------------------------------------

cat("\n=== 5. GEOGRAPHIC COVERAGE ===\n")
cities_by_country <- dataset |> distinct(city_id, country_name) |> count(country_name, sort = TRUE)
print(head(as.data.frame(cities_by_country), 5), row.names = FALSE)
cat(sprintf("Median cities per country: %.1f | Mean: %.1f\n",
            median(cities_by_country$n), mean(cities_by_country$n)))


# ------------------------------------------------------------------------------
# 6. Metric completeness — the body of Table 2
# ------------------------------------------------------------------------------

completeness <- function(cols, frame, denom, source_label) {
  tibble::tibble(
    variable = cols,
    source   = source_label,
    n_present = vapply(cols, function(v) sum(!is.na(frame[[v]])), integer(1)),
    n_total   = denom
  ) |>
    mutate(pct_complete = 100 * n_present / n_total)
}

metric_completeness <- bind_rows(
  completeness(DMSP_METRICS, dataset, n_obs, "DMSP"),
  completeness(VIIRS_METRICS, dataset_viirs, n_viirs, "VIIRS"),
  completeness(c("nl_sum_dmsp", "total_pop", "n_cells"), dataset, n_obs, "Aggregate (DMSP years)"),
  completeness("nl_sum_viirs", dataset_viirs, n_viirs, "Aggregate (VIIRS years)")
)

cat("\n=== 6. METRIC COMPLETENESS [Table 2] ===\n")

# The hierarchy of requirements should show up as a strict ordering within each
# source: Gini >= Theil >= gradients. The Gini needs two populated cells, the
# Theil needs two lit and populated cells, the gradients need five.
stray_viirs <- dataset |>
  filter(!year %in% VIIRS_YEARS) |>
  summarise(across(all_of(c(VIIRS_METRICS, "nl_sum_viirs")), ~ sum(!is.na(.x)))) |>
  sum()
cat(sprintf("VIIRS values outside %s (must be 0): %d\n",
            paste(VIIRS_YEARS, collapse = "/"), stray_viirs))


# ------------------------------------------------------------------------------
# 7. Provenance of missing values
# ------------------------------------------------------------------------------

cat("\n=== 7. MISSINGNESS HIERARCHY ===\n")
for (src in c("dmsp", "viirs")) {
  frame <- if (src == "viirs") dataset_viirs else dataset
  has_gini     <- !is.na(frame[[paste0("nl_gini_coef_", src)]])
  has_theil    <- !is.na(frame[[paste0("nl_theil_coef_", src)]])
  has_gradient <- !is.na(frame[[paste0("nl_gradient_no_pop_", src)]])

  cat(sprintf("[%s] Theil without Gini (must be 0): %d | gradient without Theil (must be 0): %d\n",
              src, sum(has_theil & !has_gini), sum(has_gradient & !has_theil)))
  cat(sprintf("[%s] Gini but no Theil (fewer than 2 lit cells): %d\n",
              src, sum(has_gini & !has_theil)))
  cat(sprintf("[%s] Theil but no gradient (2 to 4 valid cells): %d\n",
              src, sum(has_theil & !has_gradient)))
}

# Illustration quoted in the paper: Bhutan's single urban centre supports the
# dispersion indices in every year but never reaches the five-cell threshold.
cat("\nBhutan [paper: 'supports Gini and Theil ... never reaches the five-cell threshold']:\n")
dataset |>
  filter(country_name == "Bhutan") |>
  select(city_name, year, nl_gini_coef_dmsp, nl_theil_coef_dmsp,
         nl_gradient_no_pop_dmsp, n_cells) |>
  as.data.frame() |>
  print(row.names = FALSE)


# ------------------------------------------------------------------------------
# 8. Assemble Table 2
# ------------------------------------------------------------------------------

pct <- function(v, frame, denom) sprintf("%.1f%%", 100 * sum(!is.na(frame[[v]])) / denom)

table_02 <- tibble::tribble(
  ~Panel,                                  ~Indicator,                        ~Value,
  "Panel structure", "Total observations (city-year)", format(n_obs, big.mark = ","),
  "Panel structure", "Unique cities",                  format(n_cities, big.mark = ","),
  "Panel structure", "Countries",                      as.character(n_countries),
  "Panel structure", "Benchmark years",                as.character(length(BENCHMARK_YEARS)),
  "Panel structure", "Panel completeness (balanced)",  sprintf("%.1f%%", 100 * n_obs / balanced_n),
  "Panel structure", "Cities with complete panel",
    sprintf("%s (%.1f%%)", format(n_complete, big.mark = ","), 100 * n_complete / n_cities),
  "Panel structure", "Cities with incomplete panel",
    sprintf("%s (%.1f%%)", format(n_incomplete, big.mark = ","), 100 * n_incomplete / n_cities),
  "Panel structure", "Duplicate observations",         as.character(nrow(duplicates)),

  "DMSP metric completeness (all 6 years)", "Gradient (no pop. control)",
    pct("nl_gradient_no_pop_dmsp", dataset, n_obs),
  "DMSP metric completeness (all 6 years)", "Gradient (pop. control)",
    pct("nl_gradient_pop_dmsp", dataset, n_obs),
  "DMSP metric completeness (all 6 years)", "Gini coefficient",
    pct("nl_gini_coef_dmsp", dataset, n_obs),
  "DMSP metric completeness (all 6 years)", "Theil index",
    pct("nl_theil_coef_dmsp", dataset, n_obs),

  "VIIRS metric completeness (2015 and 2020 only)", "Gradient (no pop. control)",
    pct("nl_gradient_no_pop_viirs", dataset_viirs, n_viirs),
  "VIIRS metric completeness (2015 and 2020 only)", "Gradient (pop. control)",
    pct("nl_gradient_pop_viirs", dataset_viirs, n_viirs),
  "VIIRS metric completeness (2015 and 2020 only)", "Gini coefficient",
    pct("nl_gini_coef_viirs", dataset_viirs, n_viirs),
  "VIIRS metric completeness (2015 and 2020 only)", "Theil index",
    pct("nl_theil_coef_viirs", dataset_viirs, n_viirs),

  "City-level aggregates completeness", "Total luminosity, DMSP",
    pct("nl_sum_dmsp", dataset, n_obs),
  "City-level aggregates completeness", "Total luminosity, VIIRS",
    pct("nl_sum_viirs", dataset_viirs, n_viirs),
  "City-level aggregates completeness", "Total population",
    pct("total_pop", dataset, n_obs),
  "City-level aggregates completeness", "Grid cell count",
    pct("n_cells", dataset, n_obs)
)

cat("\n=== TABLE 2 ===\n")
cat(sprintf("Note: VIIRS completeness computed over N = %s observations of %s.\n",
            format(n_viirs, big.mark = ","), paste(VIIRS_YEARS, collapse = " and ")))
save_table(table_02, "table_02_data_quality.csv")

save_table(
  attrition |>
    left_join(
      dataset |> count(year, name = "n_observations"),
      by = "year"
    ),
  "table_02_panel_attrition.csv"
)

readr::write_csv(metric_completeness, path_table("table_02_metric_completeness.csv"))
log_step("Table written: ", path_table("table_02_metric_completeness.csv"))
