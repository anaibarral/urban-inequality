# ==============================================================================
# s1_ghspop.R
#
# Supplementary Information, Section S1: Tables 3 to 5 of the paper with the
# indicators computed with GHS-POP R2023A population (dataset columns *_ghs)
# instead of GPW. Same 2015 polygons, cells, lights and specifications as the
# main exhibits.
#
#   - share of negative gradients (population control), by year      ~ Table 3
#   - capital vs non-capital gradients, country FE, by year          ~ Table 4
#   - satellite vs ACS census inequality, US cities                  ~ Table 5
#
# Input   PATHS$dataset                                       (step 6)
#         <DIR_CLEAN>/case_studies/capital_panel.parquet      (capital indicator)
#         <DIR_CLEAN>/case_studies/acs_matched_{dmsp,viirs}.parquet
#           (ACS measures, city-state-year match and state of each city)
# Output  outputs/tables/table_si_ghspop_*.csv
#         outputs/tables/supplementary/table_si_ghspop_*.tex
#
# The ACS match is done on city name, state and year, so it does not depend on
# the population source. The matched samples of Table 5 are reused and the GPW
# nightlights indices are replaced by the GHS-POP ones.
# ==============================================================================

source(here::here("src", "R", "setup.R"))
source(here::here("src", "R", "plotting.R"))
source(here::here("src", "06_supplementary", "latex.R"))

library(data.table)
library(arrow)
library(fixest)

require_input(PATHS$dataset, "01_data_construction/06_consolidate_dataset.R")
DIR_CASE <- file.path(DIR_CLEAN, "case_studies")
CAPITAL_PANEL <- file.path(DIR_CASE, "capital_panel.parquet")
require_input(CAPITAL_PANEL, "03_case_study_capitals/01_build_capital_panel.R")
MATCHED <- c(DMSP = file.path(DIR_CASE, "acs_matched_dmsp.parquet"),
             VIIRS = file.path(DIR_CASE, "acs_matched_viirs.parquet"))
for (f in MATCHED) require_input(f, "04_case_study_acs/02_match_acs_to_urban_centres.R")

ds <- as.data.table(read_parquet(PATHS$dataset))
g <- ds[, .(city_id, year,
            gradient_dmsp = nl_gradient_pop_dmsp_ghs, gradient_viirs = nl_gradient_pop_viirs_ghs)]


# ------------------------------------------------------------------------------
# 1. Table 3: share of negative gradients
# ------------------------------------------------------------------------------

neg <- rbind(
  g[!is.na(gradient_dmsp), .(source = "DMSP", pct = 100 * mean(gradient_dmsp < 0), n = .N), by = year],
  g[year %in% VIIRS_YEARS & !is.na(gradient_viirs), .(source = "VIIRS", pct = 100 * mean(gradient_viirs < 0), n = .N), by = year]
)[order(source, year)]
print(neg)
save_table(neg, "table_si_ghspop_negative_gradients.csv")

mini <- function(d, title) c(
  "\\begin{minipage}[t]{0.45\\textwidth}", "\\centering", paste0("\\textbf{", title, "}\\\\"), "\\vspace{4pt}",
  "\\begin{tabular}{cc}", "\\toprule", "Year & \\% Negative \\\\", "\\midrule",
  sprintf("%d & %s\\%% \\\\", d$year, num(d$pct, 1)), "\\bottomrule", "\\end{tabular}", "\\end{minipage}")
nd <- neg[source == "DMSP"]; nv <- neg[source == "VIIRS"]
writeLines(c(
  "\\begin{table}[H]", "\\centering",
  "\\caption{Percentage of negative gradient observations (with population control), GHS-POP population}",
  "\\singlespacing",
  mini(nd, "Panel A: DMSP"), "\\hfill", mini(nv, "Panel B: VIIRS"),
  "\\begin{flushleft}",
  paste0("\\footnotesize\\textit{Note:} Proportion of city-years with negative luminosity gradients, after controlling ",
         "for population, computed over observations with estimable gradients. Population and the population control ",
         "come from GHS-POP R2023A instead of GPW. Gradient samples range from ", int(min(nd$n)), " (",
         nd$year[which.min(nd$n)], ") to ", int(max(nd$n)), " (", nd$year[which.max(nd$n)],
         ") city-years under DMSP, and VIIRS samples are ", int(nv$n[1]), " (", nv$year[1], ") and ",
         int(nv$n[2]), " (", nv$year[2], ")."),
  "\\end{flushleft}", "\\end{table}"), file.path(SI_TABLE_DIR, "table_si_ghspop_negative_gradients.tex"), useBytes = TRUE)


# ------------------------------------------------------------------------------
# 2. Table 4: capital vs non-capital gradients (country FE, SE by country)
# ------------------------------------------------------------------------------

panel <- as.data.table(read_parquet(CAPITAL_PANEL))[, .(city_id, year, country_name, capital)]
panel <- merge(panel, g, by = c("city_id", "year"))
cap <- rbindlist(lapply(c(DMSP = "gradient_dmsp", VIIRS = "gradient_viirs"), function(v) {
  yrs <- if (v == "gradient_viirs") VIIRS_YEARS else BENCHMARK_YEARS
  rbindlist(lapply(yrs, function(y) {
    d <- panel[year == y & !is.na(get(v)) & !is.na(capital) & !is.na(country_name)]
    m <- feols(as.formula(paste(v, "~ capital | country_name")), d, cluster = ~country_name, notes = FALSE)
    ct <- coeftable(m)["capital", ]
    data.table(year = y, estimate = ct[[1]], std_error = ct[[2]], p_value = ct[[4]], n_obs = nobs(m),
               n_clusters = unname(m$fixef_sizes[["country_name"]]))
  }))
}), idcol = "source")
print(cap)
save_table(cap, "table_si_ghspop_capital_gradients.csv")

cap_panel <- function(d) c(
  paste0("\\begin{tabular}{l", strrep("c", nrow(d)), "}"), "\\toprule",
  paste0(" & ", paste(sprintf("\\textbf{%d}", d$year), collapse = " & "), " \\\\"), "\\midrule",
  paste0("Capital City & ", paste(coef_tex(d$estimate, d$p_value), collapse = " & "), " \\\\"),
  paste0(" & ", paste(se_tex(d$std_error), collapse = " & "), " \\\\"), "\\midrule",
  paste0("N & ", paste(d$n_obs, collapse = " & "), " \\\\"), "\\midrule",
  paste0("Country FE & ", paste(rep("X", nrow(d)), collapse = " & "), " \\\\"), "\\bottomrule", "\\end{tabular}")
writeLines(c(
  "\\begin{table}[H]", "\\centering",
  "\\caption{NL gradient in capital vs non-capital cities (by year), GHS-POP population}",
  "\\singlespacing", "\\textbf{Panel A: DMSP}\\\\", "\\vspace{4pt}",
  "\\adjustbox{max width=\\textwidth}{", cap_panel(cap[source == "DMSP"]), "}",
  "\\vspace{10pt}", "\\\\\\textbf{Panel B: VIIRS}\\\\", "\\vspace{4pt}",
  "\\adjustbox{max width=0.4\\textwidth}{", cap_panel(cap[source == "VIIRS"]), "}",
  "\\begin{flushleft}",
  paste0("\\footnotesize\\textit{Note:} OLS regression coefficients for the capital city indicator on luminosity ",
         "gradients (with population control) computed with GHS-POP R2023A population, estimated separately for ",
         "each year, with country fixed effects. The capital indicator is that of Table 4 of the main article. ",
         "Standard errors clustered at the country level in parentheses, computed over ",
         min(cap$n_clusters), " to ", max(cap$n_clusters), " clusters depending on the year. ", STARS_NOTE),
  "\\end{flushleft}", "\\end{table}"), file.path(SI_TABLE_DIR, "table_si_ghspop_capital_gradients.tex"), useBytes = TRUE)


# ------------------------------------------------------------------------------
# 3. Table 5: satellite vs census (ACS)
# ------------------------------------------------------------------------------

ghs_nl <- list(
  DMSP  = ds[, .(city_id, year, gini_nl = nl_gini_coef_dmsp_ghs, theil_nl = nl_theil_coef_dmsp_ghs)],
  VIIRS = ds[year %in% VIIRS_YEARS, .(city_id, year, gini_nl = nl_gini_coef_viirs_ghs, theil_nl = nl_theil_coef_viirs_ghs)])
samples <- lapply(names(MATCHED), function(s) {
  m <- as.data.table(read_parquet(MATCHED[[s]]))[, .(city_id, year, state_code, gini_acs, theil_acs)]
  merge(m, ghs_nl[[s]], by = c("city_id", "year"))[!is.na(gini_nl) & !is.na(theil_nl)]
})
names(samples) <- names(MATCHED)

trio <- function(d, y, x) {
  specs <- c(sprintf("%s ~ %s", y, x), sprintf("%s ~ %s | year", y, x), sprintf("%s ~ %s | state_code + year", y, x))
  rbindlist(lapply(seq_along(specs), function(k) {
    m <- feols(as.formula(specs[k]), d, cluster = ~city_id, notes = FALSE, warn = FALSE)
    ct <- coeftable(m)[x, ]
    data.table(spec = k, estimate = ct[[1]], std_error = ct[[2]], p_value = ct[[4]], n_obs = nobs(m),
               r_squared = unname(fixest::r2(m, "r2")))
  }))
}
acs_res <- rbindlist(lapply(names(samples), function(s) rbind(
  trio(samples[[s]], "gini_acs", "gini_nl")[, `:=`(source = s, measure = "Gini")],
  trio(samples[[s]], "theil_acs", "theil_nl")[, `:=`(source = s, measure = "Theil")])))
setcolorder(acs_res, c("source", "measure"))
print(acs_res)
save_table(acs_res, "table_si_ghspop_acs_validation.csv")

acs_body <- function(res) {
  gi <- res[measure == "Gini"]; th <- res[measure == "Theil"]
  blank3 <- rep("", 3)
  c("\\begin{tabular}{lcccccc}", "\\toprule",
    " & \\multicolumn{3}{c}{ACS Gini} & \\multicolumn{3}{c}{ACS Theil} \\\\",
    " \\cmidrule(lr){2-4} \\cmidrule(lr){5-7}",
    " & (1) & (2) & (3) & (4) & (5) & (6) \\\\", "\\midrule",
    paste0("Nightlights Gini & ", paste(c(coef_tex(gi$estimate, gi$p_value), blank3), collapse = " & "), " \\\\"),
    paste0(" & ", paste(c(se_tex(gi$std_error), blank3), collapse = " & "), " \\\\"),
    "\\addlinespace",
    paste0("Nightlights Theil & ", paste(c(blank3, coef_tex(th$estimate, th$p_value)), collapse = " & "), " \\\\"),
    paste0(" & ", paste(c(blank3, se_tex(th$std_error)), collapse = " & "), " \\\\"),
    "\\midrule",
    paste0("N & ", paste(c(gi$n_obs, th$n_obs), collapse = " & "), " \\\\"),
    paste0("$R^2$ & ", paste(num(c(gi$r_squared, th$r_squared)), collapse = " & "), " \\\\"),
    "\\midrule", "FE Year & & X & & & X & \\\\", "FE State + Year & & & X & & & X \\\\",
    "\\bottomrule", "\\end{tabular}")
}
nA <- acs_res[source == "DMSP"]$n_obs[1]; nB <- acs_res[source == "VIIRS"]$n_obs[1]
writeLines(c(
  "\\begin{table}[H]", "\\centering",
  "\\caption{Regression analysis: satellite-based inequality vs.\\ census data, GHS-POP population}",
  "\\singlespacing",
  sprintf("\\textbf{Panel A: DMSP} ($N = %d$, U.S.\\ cities, 2000--2020)\\\\", nA), "\\vspace{4pt}",
  "\\adjustbox{max width=\\textwidth}{", acs_body(acs_res[source == "DMSP"]), "}",
  "\\vspace{10pt}",
  sprintf("\\\\\\textbf{Panel B: VIIRS} ($N = %d$, U.S.\\ cities, 2015--2020)\\\\", nB), "\\vspace{4pt}",
  "\\adjustbox{max width=\\textwidth}{", acs_body(acs_res[source == "VIIRS"]), "}",
  "\\begin{flushleft}",
  paste0("\\footnotesize\\textit{Note:} Panel regression coefficients relating satellite-derived inequality measures ",
         "(NTL Gini and NTL Theil) computed with GHS-POP R2023A population to census-based inequality from the ",
         "American Community Survey. The ACS measures and the matched cities are those of Table 5 of the main ",
         "article. Columns (1)--(3) use ACS Gini as dependent variable, and columns (4)--(6) use ACS Theil. ",
         "Standard errors clustered by city in parentheses. FE = fixed effects. ", STARS_NOTE),
  "\\end{flushleft}", "\\end{table}"), file.path(SI_TABLE_DIR, "table_si_ghspop_acs_validation.tex"), useBytes = TRUE)


log_step("Supplementary tables with GHS-POP population complete.")
