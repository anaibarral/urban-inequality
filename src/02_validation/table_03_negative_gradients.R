# ==============================================================================
# table_03_negative_gradients.R
#
# Reproduces TABLE 3 of the paper, "Percentage of negative gradient observations
# (with population control)", Panel A (DMSP, 1995-2020) and Panel B (VIIRS,
# 2015-2020).
#
# Input   PATHS$dataset   (01_data_construction/06_consolidate_dataset.R)
# Output  outputs/tables/table_03_negative_gradients.csv
#
# The share is computed over city-years with an ESTIMABLE gradient, not over all
# city-years. A city-year whose gradient could not be estimated has no sign, so
# counting it in the denominator would mix a statement about urban structure
# with a statement about data coverage. `mean(x < 0, na.rm = TRUE)` implements
# that: it divides by the number of non-missing values.
#
# The sample sizes are reported alongside each share, since the paper's note
# quotes them ("Gradient samples range from 10,642 (1995) to 11,245 (2010)").
# ==============================================================================

source(here::here("src", "R", "setup.R"))
source(here::here("src", "R", "plotting.R"))

library(dplyr)
library(tidyr)
library(arrow)

require_input(PATHS$dataset, "01_data_construction/06_consolidate_dataset.R")

dataset <- read_parquet(PATHS$dataset)


# ------------------------------------------------------------------------------
# Shares by year and specification
# ------------------------------------------------------------------------------

share_negative <- function(frame, column, source_label, specification) {
  frame |>
    group_by(year) |>
    summarise(
      n_estimable = sum(!is.na(.data[[column]])),
      pct_negative = 100 * mean(.data[[column]] < 0, na.rm = TRUE),
      .groups = "drop"
    ) |>
    mutate(source = source_label, specification = specification, .before = 1)
}

dataset_viirs <- filter(dataset, year %in% VIIRS_YEARS)

table_03 <- bind_rows(
  share_negative(dataset,       "nl_gradient_pop_dmsp",     "DMSP",  "With population control"),
  share_negative(dataset_viirs, "nl_gradient_pop_viirs",    "VIIRS", "With population control"),
  share_negative(dataset,       "nl_gradient_no_pop_dmsp",  "DMSP",  "Without population control"),
  share_negative(dataset_viirs, "nl_gradient_no_pop_viirs", "VIIRS", "Without population control")
) |>
  mutate(
    year = as.integer(year),
    pct_negative = round(pct_negative, 1)
  ) |>
  arrange(desc(specification), source, year)


# ------------------------------------------------------------------------------
# Report
# ------------------------------------------------------------------------------

cat("\n=== TABLE 3: share of city-years with a negative gradient ===\n")
cat("Panel A: DMSP, with population control\n")
table_03 |>
  filter(source == "DMSP", specification == "With population control") |>
  select(Year = year, `% Negative` = pct_negative, N = n_estimable) |>
  as.data.frame() |> print(row.names = FALSE)

cat("\nPanel B: VIIRS, with population control\n")
table_03 |>
  filter(source == "VIIRS", specification == "With population control") |>
  select(Year = year, `% Negative` = pct_negative, N = n_estimable) |>
  as.data.frame() |> print(row.names = FALSE)

cat("\nAppendix: without population control\n")
table_03 |>
  filter(specification == "Without population control") |>
  select(Source = source, Year = year, `% Negative` = pct_negative, N = n_estimable) |>
  as.data.frame() |> print(row.names = FALSE)

save_table(table_03, "table_03_negative_gradients.csv")

log_step("Table 3 complete.")
