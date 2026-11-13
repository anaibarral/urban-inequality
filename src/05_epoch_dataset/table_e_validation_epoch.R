# ==============================================================================
# table_e_validation_epoch.R
#
# Validation of the epoch dataset with the tests applied to the main dataset:
# Table 3 (share of negative gradients), Table 4 (capital vs non-capital),
# Table 5 (satellite vs census inequality) and Table 6 (pairwise correlations),
# each computed with GPW and with GHS-POP population.
#
# Input   PATHS$epoch_dataset          (05_consolidate_dataset.R)
#         PATHS$acs_gini, PATHS$acs_theil
#         PATH_UCDB_MTUC               urban centre points, for the US state
# Output  outputs/tables/table_e03_negative_gradients_epoch.csv
#         outputs/tables/table_e04_capital_gradients_epoch.csv
#         outputs/tables/table_e05_acs_validation_epoch.csv
#         outputs/tables/table_e06_pairwise_correlations_epoch.csv
#
# Differences with the main exhibits, all due to the R2024A database:
#   - Capital status is the database's own indicator (is_capital), not a match
#     on names against a reference list.
#   - The US state of each urban centre comes from its R2024A point.
#   - In Table 5, a city name that appears twice in the same state and year is
#     ambiguous in the census match, and those city-years are dropped.
# ==============================================================================

source(here::here("src", "R", "setup.R"))
source(here::here("src", "R", "plotting.R"))

library(dplyr)
library(tidyr)
library(purrr)
library(fixest)
library(sf)
library(arrow)
library(readxl)

require_input(PATHS$epoch_dataset, "05_epoch_dataset/05_consolidate_dataset.R")
epoch <- read_parquet(PATHS$epoch_dataset)

stars <- function(p) case_when(p < 0.01 ~ "***", p < 0.05 ~ "**", p < 0.10 ~ "*", TRUE ~ "")

#' The epoch dataset with the metrics of one population source under the
#' unsuffixed names, so that one set of specifications serves both sources.
with_population <- function(pp) {
  sfx <- paste0("_", pp)
  cols <- grep(paste0("^nl_(gradient|gini|theil).*", sfx, "$"), names(epoch), value = TRUE)
  epoch |>
    dplyr::select(city_id = city_id_epoch_ucdb2024, city_name, country_name, iso_code, year, is_capital,
                  dplyr::all_of(cols)) |>
    dplyr::rename_with(~ sub(paste0(sfx, "$"), "", .x), dplyr::all_of(cols))
}

populations <- c(GPW = "gpw", `GHS-POP` = "ghs")
panels <- purrr::map(populations, with_population)

gradient_specs <- tibble::tribble(
  ~source, ~outcome,                   ~years,           ~specification,
  "DMSP",  "nl_gradient_pop_dmsp",     BENCHMARK_YEARS,  "With population control",
  "VIIRS", "nl_gradient_pop_viirs",    VIIRS_YEARS,      "With population control",
  "DMSP",  "nl_gradient_no_pop_dmsp",  BENCHMARK_YEARS,  "Without population control",
  "VIIRS", "nl_gradient_no_pop_viirs", VIIRS_YEARS,      "Without population control"
)


# ------------------------------------------------------------------------------
# Table 3: share of negative gradients
# ------------------------------------------------------------------------------

table_e03 <- purrr::imap_dfr(panels, function(d, pop_label) {
  purrr::pmap_dfr(gradient_specs, function(source, outcome, years, specification) {
    d |>
      dplyr::filter(year %in% years, !is.na(.data[[outcome]])) |>
      dplyr::group_by(year) |>
      dplyr::summarise(pct_negative = round(100 * mean(.data[[outcome]] < 0), 1),
                       n_estimable = dplyr::n(), .groups = "drop") |>
      dplyr::mutate(population = pop_label, source = source, specification = specification, .before = 1)
  })
})


# ------------------------------------------------------------------------------
# Table 4: capital vs non-capital gradients (country FE, SE clustered by country)
# ------------------------------------------------------------------------------

table_e04 <- purrr::imap_dfr(panels, function(d, pop_label) {
  purrr::pmap_dfr(gradient_specs, function(source, outcome, years, specification) {
    purrr::map_dfr(years, function(y) {
      m <- feols(as.formula(paste0(outcome, " ~ is_capital | country_name")),
                 data = dplyr::filter(d, year == y, !is.na(.data[[outcome]]), !is.na(is_capital)),
                 cluster = ~ country_name, notes = FALSE, warn = FALSE)
      ct <- coeftable(m)["is_capital", ]
      tibble::tibble(population = pop_label, source = source, specification = specification, year = y,
                     estimate = ct[[1]], std_error = ct[[2]], p_value = ct[[4]], n_obs = nobs(m),
                     coefficient = sprintf("%.3f%s", ct[[1]], stars(ct[[4]])))
    })
  })
})


# ------------------------------------------------------------------------------
# Table 5: satellite vs census (ACS), SE clustered by city
# ------------------------------------------------------------------------------

split_city_state <- function(df) {
  df |>
    dplyr::filter(CITY_NAME != "Not in identifiable city (or size group)") |>
    dplyr::mutate(city_name = trimws(gsub(",.*", "", CITY_NAME)),
                  state_abb = trimws(sub("^[^,]*,", "", CITY_NAME)))
}
acs <- dplyr::inner_join(
  read_excel(PATHS$acs_gini) |> split_city_state() |>
    dplyr::select(city_name, state_abb, state_code = STATEFIP, year, gini_acs = gini),
  read_excel(PATHS$acs_theil) |> split_city_state() |>
    dplyr::select(city_name, state_abb, year, theil_acs = theil),
  by = c("city_name", "state_abb", "year"))

us_ids <- unique(epoch$city_id_epoch_ucdb2024[epoch$iso_code %in% "USA"])
points <- st_read(PATH_UCDB_MTUC, layer = "GHSL_UCDB_MTUC_GLOBE_R2024", quiet = TRUE)
points <- st_transform(points[points$ID_MTUC_G0 %in% us_ids, "ID_MTUC_G0"], 4326)
options(tigris_use_cache = TRUE)
us_states <- tigris::states(cb = TRUE, progress_bar = FALSE) |>
  dplyr::select(state_abb = STUSPS) |>
  st_transform(4326)
sf_use_s2(FALSE)
state_lookup <- st_join(points, us_states)
outside <- is.na(state_lookup$state_abb)
if (any(outside)) {
  state_lookup$state_abb[outside] <- us_states$state_abb[st_nearest_feature(state_lookup[outside, ], us_states)]
}
state_lookup <- state_lookup |> st_drop_geometry() |> dplyr::select(city_id = ID_MTUC_G0, state_abb)

table_e05 <- purrr::imap_dfr(panels, function(d, pop_label) {
  purrr::map_dfr(c("dmsp", "viirs"), function(src) {
    g <- paste0("nl_gini_coef_", src)
    th <- paste0("nl_theil_coef_", src)
    sample <- d |>
      dplyr::filter(iso_code %in% "USA", if (src == "viirs") year %in% VIIRS_YEARS else TRUE,
                    !is.na(.data[[g]]), !is.na(.data[[th]])) |>
      dplyr::transmute(city_id, city_name, year, gini_nl = .data[[g]], theil_nl = .data[[th]]) |>
      dplyr::inner_join(state_lookup, by = "city_id") |>
      dplyr::inner_join(acs, by = c("city_name", "state_abb", "year")) |>
      dplyr::group_by(city_name, state_abb, year) |>
      dplyr::filter(dplyr::n() == 1) |>
      dplyr::ungroup()
    purrr::map_dfr(c("gini", "theil"), function(meas) {
      y <- paste0(meas, "_acs")
      x <- paste0(meas, "_nl")
      specs <- c(`(1) No FE` = sprintf("%s ~ %s", y, x),
                 `(2) Year FE` = sprintf("%s ~ %s | year", y, x),
                 `(3) State + Year FE` = sprintf("%s ~ %s | state_code + year", y, x))
      purrr::imap_dfr(specs, function(f, spec) {
        m <- feols(as.formula(f), data = sample, cluster = ~ city_id, notes = FALSE, warn = FALSE)
        ct <- coeftable(m)[x, ]
        tibble::tibble(population = pop_label, source = toupper(src), measure = tools::toTitleCase(meas),
                       specification = spec, estimate = ct[[1]], std_error = ct[[2]], p_value = ct[[4]],
                       n_obs = nobs(m), r_squared = unname(fixest::r2(m, "r2")),
                       coefficient = sprintf("%.3f%s", ct[[1]], stars(ct[[4]])))
      })
    })
  })
})


# ------------------------------------------------------------------------------
# Table 6: pairwise correlations (complete cases per pair)
# ------------------------------------------------------------------------------

pair_cor <- function(d, a, b) {
  x <- stats::na.omit(d[c(a, b)])
  if (nrow(x) < 3) return(NA_real_)
  round(stats::cor(x[[1]], x[[2]]), 3)
}

table_e06 <- purrr::imap_dfr(panels, function(d, pop_label) {
  dv <- dplyr::filter(d, year %in% VIIRS_YEARS)
  tibble::tibble(
    population      = pop_label,
    A_gini_theil    = pair_cor(d,  "nl_gini_coef_dmsp",  "nl_theil_coef_dmsp"),
    A_gini_gradient = pair_cor(d,  "nl_gini_coef_dmsp",  "nl_gradient_pop_dmsp"),
    B_gini_theil    = pair_cor(dv, "nl_gini_coef_viirs", "nl_theil_coef_viirs"),
    B_gini_gradient = pair_cor(dv, "nl_gini_coef_viirs", "nl_gradient_pop_viirs"),
    C_gini          = pair_cor(dv, "nl_gini_coef_dmsp",  "nl_gini_coef_viirs"),
    C_theil         = pair_cor(dv, "nl_theil_coef_dmsp", "nl_theil_coef_viirs"),
    C_gradient_pop    = pair_cor(dv, "nl_gradient_pop_dmsp",    "nl_gradient_pop_viirs"),
    C_gradient_no_pop = pair_cor(dv, "nl_gradient_no_pop_dmsp", "nl_gradient_no_pop_viirs")
  )
})


# ------------------------------------------------------------------------------
# Report and write
# ------------------------------------------------------------------------------

cat("\n=== Epoch dataset: share of negative gradients ===\n")
print(tidyr::pivot_wider(table_e03, id_cols = c(specification, source, year), names_from = population,
                         values_from = pct_negative), n = Inf)
cat("\n=== Epoch dataset: capital coefficient ===\n")
print(tidyr::pivot_wider(table_e04, id_cols = c(specification, source, year), names_from = population,
                         values_from = coefficient), n = Inf)
cat("\n=== Epoch dataset: ACS validation ===\n")
print(tidyr::pivot_wider(table_e05, id_cols = c(source, measure, specification), names_from = population,
                         values_from = coefficient), n = Inf)
cat("\n=== Epoch dataset: pairwise correlations ===\n")
print(as.data.frame(table_e06))

save_table(table_e03, "table_e03_negative_gradients_epoch.csv")
save_table(table_e04, "table_e04_capital_gradients_epoch.csv")
save_table(table_e05, "table_e05_acs_validation_epoch.csv")
save_table(table_e06, "table_e06_pairwise_correlations_epoch.csv")

log_step("Epoch validation tables complete.")
