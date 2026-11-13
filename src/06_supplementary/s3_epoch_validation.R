# ==============================================================================
# s3_epoch_validation.R
#
# Supplementary Information, Section S3: Tables 3 to 5 of the paper computed on the
# epoch dataset (GHS-UCDB R2024A polygons of each epoch), DMSP lights and GPW
# population, with the specifications of the main exhibits.
#
#   - share of negative gradients (population control), by year      ~ Table 3A
#   - capital vs non-capital gradients, country FE, by year          ~ Table 4A
#   - satellite vs ACS census inequality, US cities                  ~ Table 5A
#
# Input   PATHS$epoch_dataset          (05_epoch_dataset/05_consolidate_dataset.R)
#         PATHS$acs_gini, PATHS$acs_theil (bundled)
#         PATH_UCDB_MTUC               urban center points, for the US state
# Output  outputs/tables/table_si_epoch_*.csv
#         outputs/tables/supplementary/table_si_epoch_*.tex
#
# Differences with the main exhibits, all due to the R2024A database:
#   - Capital status is the database's own indicator (is_capital).
#   - The US state of each urban center comes from its R2024A point, and the
#     ACS match uses the R2024A name. A name that appears twice in the same state
#     and year is ambiguous, and those city-years are dropped.
# ==============================================================================

source(here::here("src", "R", "setup.R"))
source(here::here("src", "R", "plotting.R"))
source(here::here("src", "06_supplementary", "latex.R"))

library(dplyr)
library(tidyr)
library(purrr)
library(fixest)
library(sf)
library(arrow)
library(readxl)

require_input(PATHS$epoch_dataset, "05_epoch_dataset/05_consolidate_dataset.R")

d <- read_parquet(PATHS$epoch_dataset) |>
  dplyr::transmute(city_id = city_id_epoch_ucdb2024, city_name, country_name, iso_code, year, is_capital,
                   gradient = nl_gradient_pop_dmsp_gpw, gini = nl_gini_coef_dmsp_gpw, theil = nl_theil_coef_dmsp_gpw)


# ------------------------------------------------------------------------------
# Table 3: share of negative gradients
# ------------------------------------------------------------------------------

s1 <- d |>
  dplyr::filter(!is.na(gradient)) |>
  dplyr::group_by(year) |>
  dplyr::summarise(pct_negative = 100 * mean(gradient < 0), n = dplyr::n(), .groups = "drop")
print(s1)
save_table(s1, "table_si_epoch_negative_gradients.csv")

write_si_table(
  "table_si_epoch_negative_gradients.tex",
  "Percentage of negative gradient observations (with population control), time-varying urban boundaries, DMSP",
  "ccc",
  c("\\toprule", "Year & \\% Negative & City-years \\\\", "\\midrule",
    sprintf("%d & %s\\%% & %s \\\\", s1$year, num(s1$pct_negative, 1), int(s1$n)),
    "\\bottomrule"),
  paste0("Proportion of urban center-years with negative luminosity gradients (declining luminosity from ",
         "center to periphery), after controlling for population, computed over observations with estimable ",
         "gradients. Each urban center is measured inside its GHS-UCDB R2024A polygon of the corresponding epoch. ",
         "DMSP lights and GPW population. The epoch panel contains ", int(nrow(d)), " urban center-years for ",
         int(dplyr::n_distinct(d$city_id)), " urban centers.")
)


# ------------------------------------------------------------------------------
# Table 4: capital vs non-capital gradients
# ------------------------------------------------------------------------------

s2 <- purrr::map_dfr(BENCHMARK_YEARS, function(y) {
  sample <- dplyr::filter(d, year == y, !is.na(gradient))
  m <- feols(gradient ~ is_capital | country_name, data = sample, cluster = ~country_name, notes = FALSE, warn = FALSE)
  ct <- coeftable(m)["is_capital", ]
  tibble::tibble(year = y, estimate = ct[[1]], std_error = ct[[2]], p_value = ct[[4]], n_obs = nobs(m),
                 n_clusters = length(unique(sample$country_name[obs(m)])),
                 n_capitals = sum(sample$is_capital[obs(m)]))
})
print(s2)
save_table(s2, "table_si_epoch_capital_gradients.csv")

write_si_table(
  "table_si_epoch_capital_gradients.tex",
  "NL gradient in capital vs non-capital cities (by year), time-varying urban boundaries, DMSP",
  "lcccccc",
  c("\\toprule",
    paste0(" & ", paste(sprintf("\\textbf{%d}", s2$year), collapse = " & "), " \\\\"),
    "\\midrule",
    paste0("Capital City & ", paste(coef_tex(s2$estimate, s2$p_value), collapse = " & "), " \\\\"),
    paste0(" & ", paste(se_tex(s2$std_error), collapse = " & "), " \\\\"),
    "\\midrule",
    paste0("N & ", paste(s2$n_obs, collapse = " & "), " \\\\"),
    "\\midrule",
    paste0("Country FE & ", paste(rep("X", nrow(s2)), collapse = " & "), " \\\\"),
    "\\bottomrule"),
  paste0("OLS regression coefficients for the capital city indicator on luminosity gradients (with population ",
         "control), estimated separately for each year, with country fixed effects. Capital status is the ",
         "GHS-UCDB R2024A indicator of the urban center that contains the national capital. Standard errors ",
         "clustered at the country level in parentheses, computed over ", min(s2$n_clusters), " to ",
         max(s2$n_clusters), " clusters depending on the year. ", STARS_NOTE),
  size = "\\small"
)


# ------------------------------------------------------------------------------
# Table 5: satellite vs census (ACS)
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

us_ids <- unique(d$city_id[d$iso_code %in% "USA"])
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

acs_sample <- d |>
  dplyr::filter(iso_code %in% "USA", !is.na(gini), !is.na(theil)) |>
  dplyr::select(city_id, city_name, year, gini_nl = gini, theil_nl = theil) |>
  dplyr::inner_join(state_lookup, by = "city_id") |>
  dplyr::inner_join(acs, by = c("city_name", "state_abb", "year")) |>
  dplyr::group_by(city_name, state_abb, year) |>
  dplyr::filter(dplyr::n() == 1) |>
  dplyr::ungroup()

census_specs <- function(sample, y, x, cluster, state = "state_code") {
  specs <- c(sprintf("%s ~ %s", y, x), sprintf("%s ~ %s | year", y, x), sprintf("%s ~ %s | %s + year", y, x, state))
  purrr::map_dfr(seq_along(specs), function(k) {
    m <- feols(as.formula(specs[k]), data = sample, cluster = cluster, notes = FALSE, warn = FALSE)
    ct <- coeftable(m)[x, ]
    tibble::tibble(spec = k, estimate = ct[[1]], std_error = ct[[2]], p_value = ct[[4]], n_obs = nobs(m),
                   r_squared = unname(fixest::r2(m, "r2")))
  })
}
s3 <- dplyr::bind_rows(
  census_specs(acs_sample, "gini_acs", "gini_nl", ~city_id) |> dplyr::mutate(measure = "Gini", .before = 1),
  census_specs(acs_sample, "theil_acs", "theil_nl", ~city_id) |> dplyr::mutate(measure = "Theil", .before = 1)
)
print(s3)
save_table(s3, "table_si_epoch_acs_validation.csv")

#' Body of a Table 5-style panel: Gini in columns (1)-(3), Theil in (4)-(6).
census_panel_body <- function(res, xlab_gini = "Nightlights Gini", xlab_theil = "Nightlights Theil",
                              fe_state = "FE State + Year") {
  g <- dplyr::filter(res, measure == "Gini"); t <- dplyr::filter(res, measure == "Theil")
  blank3 <- rep("", 3)
  c("\\toprule",
    " & \\multicolumn{3}{c}{Census Gini} & \\multicolumn{3}{c}{Census Theil} \\\\",
    " \\cmidrule(lr){2-4} \\cmidrule(lr){5-7}",
    " & (1) & (2) & (3) & (4) & (5) & (6) \\\\",
    "\\midrule",
    paste0(xlab_gini, " & ", paste(c(coef_tex(g$estimate, g$p_value), blank3), collapse = " & "), " \\\\"),
    paste0(" & ", paste(c(se_tex(g$std_error), blank3), collapse = " & "), " \\\\"),
    "\\addlinespace",
    paste0(xlab_theil, " & ", paste(c(blank3, coef_tex(t$estimate, t$p_value)), collapse = " & "), " \\\\"),
    paste0(" & ", paste(c(blank3, se_tex(t$std_error)), collapse = " & "), " \\\\"),
    "\\midrule",
    paste0("N & ", paste(c(g$n_obs, t$n_obs), collapse = " & "), " \\\\"),
    paste0("$R^2$ & ", paste(num(c(g$r_squared, t$r_squared)), collapse = " & "), " \\\\"),
    "\\midrule",
    "FE Year & & X & & & X & \\\\",
    paste0(fe_state, " & & & X & & & X \\\\"),
    "\\bottomrule")
}

write_si_table(
  "table_si_epoch_acs_validation.tex",
  "Regression analysis: satellite-based inequality vs.\\ census data, time-varying urban boundaries, DMSP",
  "lcccccc",
  sub("Census Gini", "ACS Gini", sub("Census Theil", "ACS Theil", census_panel_body(s3))),
  paste0("Panel regression coefficients relating DMSP-based inequality measures (NTL Gini and NTL Theil) of ",
         "urban centers measured inside their GHS-UCDB R2024A polygon of each epoch to census-based inequality ",
         "from the American Community Survey, U.S.\\ cities, 2000--2020. Columns (1)--(3) use ACS Gini as ",
         "dependent variable, and columns (4)--(6) use ACS Theil. Standard errors clustered by city in ",
         "parentheses. N = ", s3$n_obs[1], " city-year observations",
         if (length(unique(s3$n_obs[s3$spec == 3])) == 1 && s3$n_obs[s3$spec == 3][1] != s3$n_obs[1])
           sprintf(" (%d in columns 3 and 6)", s3$n_obs[s3$spec == 3][1]) else "",
         ". FE = fixed effects. ", STARS_NOTE),
  size = "\\small"
)


log_step("Supplementary tables on time-varying boundaries complete.")
