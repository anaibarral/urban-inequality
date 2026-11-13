# ==============================================================================
# table_si_census_validation.R
#
# Supplementary Information, Section S5: Table 5 of the paper with census data for Mexico and
# Brazil, on the epoch dataset (DMSP lights, GPW population).
#
#   Panel A  Mexico, 2010-2020: inequality of household labour income in the
#            localities of 50,000 or more inside each urban center (INEGI)
#   Panel B  Brazil, 2000-2010: inequality of total household income in the
#            municipality covering the largest share of each urban center (IBGE)
#
# Input   PATHS$epoch_dataset
#         PATHS$mexico_census                       (bundled; step 01)
#         PATHS$brazil_census, PATHS$brazil_crosswalk (bundled; step 02)
# Output  outputs/tables/table_si_census_mexico_brazil.csv
#         outputs/tables/supplementary/table_si_census_mexico_brazil.tex
#
# Specifications as in Table 5: no fixed effects, year fixed effects, and state
# plus year fixed effects; standard errors clustered by urban center.
# ==============================================================================

source(here::here("src", "R", "setup.R"))
source(here::here("src", "R", "plotting.R"))
source(here::here("src", "06_supplementary", "latex.R"))

library(dplyr)
library(purrr)
library(fixest)
library(arrow)
library(readr)

require_input(PATHS$epoch_dataset, "05_epoch_dataset/05_consolidate_dataset.R")
require_input(PATHS$mexico_census, "06_supplementary/01_mexico_census_inequality.R")
require_input(PATHS$brazil_census, "06_supplementary/02_brazil_census_inequality.R")
require_input(PATHS$brazil_crosswalk, "06_supplementary/02_brazil_census_inequality.R")

epoch <- read_parquet(PATHS$epoch_dataset) |>
  dplyr::transmute(city_id_epoch_ucdb2024, year, iso_code,
                   gini_nl = nl_gini_coef_dmsp_gpw, theil_nl = nl_theil_coef_dmsp_gpw)

mexico <- read_csv(PATHS$mexico_census, show_col_types = FALSE) |>
  dplyr::inner_join(dplyr::filter(epoch, iso_code == "MEX"), by = c("city_id_epoch_ucdb2024", "year"))

brazil <- read_csv(PATHS$brazil_crosswalk, show_col_types = FALSE) |>
  dplyr::inner_join(read_csv(PATHS$brazil_census, show_col_types = FALSE), by = c("code_muni", "year")) |>
  dplyr::inner_join(dplyr::filter(epoch, iso_code == "BRA"), by = c("city_id_epoch_ucdb2024", "year"))

census_regressions <- function(sample, country) {
  purrr::map_dfr(c(Gini = "gini", Theil = "theil"), function(m) {
    y <- paste0(m, "_census"); x <- paste0(m, "_nl")
    s <- dplyr::filter(sample, !is.na(.data[[x]]), !is.na(.data[[y]]))
    specs <- c(sprintf("%s ~ %s", y, x), sprintf("%s ~ %s | year", y, x), sprintf("%s ~ %s | state_code + year", y, x))
    purrr::map_dfr(seq_along(specs), function(k) {
      fit <- feols(as.formula(specs[k]), data = s, cluster = ~city_id_epoch_ucdb2024, notes = FALSE, warn = FALSE)
      ct <- coeftable(fit)[x, ]
      tibble::tibble(country = country, measure = tools::toTitleCase(m), spec = k,
                     estimate = ct[[1]], std_error = ct[[2]], p_value = ct[[4]], n_obs = nobs(fit),
                     n_cities = length(unique(s$city_id_epoch_ucdb2024[obs(fit)])),
                     r_squared = unname(fixest::r2(fit, "r2")))
    })
  }, .id = NULL)
}
s4 <- dplyr::bind_rows(census_regressions(mexico, "Mexico"), census_regressions(brazil, "Brazil"))
print(as.data.frame(s4))
save_table(s4, "table_si_census_mexico_brazil.csv")


# ------------------------------------------------------------------------------
# LaTeX: two panels in the layout of Table 5
# ------------------------------------------------------------------------------

panel <- function(res) {
  g <- dplyr::filter(res, measure == "Gini"); t <- dplyr::filter(res, measure == "Theil")
  blank3 <- rep("", 3)
  c(" & \\multicolumn{3}{c}{Census Gini} & \\multicolumn{3}{c}{Census Theil} \\\\",
    " \\cmidrule(lr){2-4} \\cmidrule(lr){5-7}",
    " & (1) & (2) & (3) & (4) & (5) & (6) \\\\",
    "\\midrule",
    paste0("Nightlights Gini & ", paste(c(coef_tex(g$estimate, g$p_value), blank3), collapse = " & "), " \\\\"),
    paste0(" & ", paste(c(se_tex(g$std_error), blank3), collapse = " & "), " \\\\"),
    "\\addlinespace",
    paste0("Nightlights Theil & ", paste(c(blank3, coef_tex(t$estimate, t$p_value)), collapse = " & "), " \\\\"),
    paste0(" & ", paste(c(blank3, se_tex(t$std_error)), collapse = " & "), " \\\\"),
    "\\midrule",
    paste0("N & ", paste(c(g$n_obs, t$n_obs), collapse = " & "), " \\\\"),
    paste0("$R^2$ & ", paste(num(c(g$r_squared, t$r_squared)), collapse = " & "), " \\\\"),
    "\\midrule",
    "FE Year & & X & & & X & \\\\",
    "FE State + Year & & & X & & & X \\\\",
    "\\bottomrule")
}
mx <- dplyr::filter(s4, country == "Mexico"); br <- dplyr::filter(s4, country == "Brazil")
body <- c(
  "\\toprule",
  sprintf("\\multicolumn{7}{l}{\\textbf{Panel A: Mexico} (localities of 50,000 or more, 2010--2020, $N = %d$)} \\\\",
          mx$n_obs[1]),
  "\\midrule",
  panel(mx),
  "\\addlinespace[8pt]",
  "\\toprule",
  sprintf("\\multicolumn{7}{l}{\\textbf{Panel B: Brazil} (municipalities, 2000--2010, $N = %d$)} \\\\", br$n_obs[1]),
  "\\midrule",
  panel(br)
)
write_si_table(
  "table_si_census_mexico_brazil.tex",
  "Regression analysis: satellite-based inequality vs.\\ census data for Mexico and Brazil, DMSP",
  "lcccccc",
  body,
  paste0("Panel regression coefficients relating DMSP-based inequality measures (NTL Gini and NTL Theil, GPW ",
         "population) of urban centers measured inside their GHS-UCDB R2024A polygon of each epoch to census-based ",
         "inequality. Panel A: Gini and Theil of household income from work (INEGI, Censo de Poblaci\\'on y ",
         "Vivienda 2010 and 2020, sample, and Encuesta Intercensal 2015), pooling the households of the localities ",
         "of 50,000 inhabitants or more located inside each urban center (", max(mx$n_cities),
         " urban centers). Panel B: Gini and Theil of total household income (IBGE, Censo ",
         "Demogr\\'afico 2000 and 2010, sample) in the municipality that covers the largest share of each urban ",
         "center (", max(br$n_cities), " urban centers). Columns (1)--(3) use the census Gini as dependent ",
         "variable, and columns (4)--(6) use the census Theil. Standard errors clustered by urban center in ",
         "parentheses. FE = fixed effects. ", STARS_NOTE),
  size = "\\small"
)

log_step("Supplementary table on census data for Mexico and Brazil complete.")
