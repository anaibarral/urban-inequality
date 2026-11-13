# ==============================================================================
# s2_pwc_gradients.R
#
# Supplementary Information, Section S2: Tables 3 and 4 of the paper with
# the luminosity gradients measured from the population-weighted centroid of
# each city-year (dataset columns nl_gradient_pwc_*, built in step 4b) instead
# of the city centroid of the main dataset (st_point_on_surface). GPW
# population, with population control, as in the main exhibits.
#
# Input   PATHS$dataset                                  (step 6)
#         <DIR_CLEAN>/case_studies/capital_panel.parquet (capital indicator)
# Output  outputs/tables/table_si_pwc_*.csv
#         outputs/tables/supplementary/table_si_pwc_*.tex
# ==============================================================================

source(here::here("src", "R", "setup.R"))
source(here::here("src", "R", "plotting.R"))
source(here::here("src", "06_supplementary", "latex.R"))

library(data.table)
library(arrow)
library(fixest)

require_input(PATHS$dataset, "01_data_construction/06_consolidate_dataset.R")
CAPITAL_PANEL <- file.path(DIR_CLEAN, "case_studies", "capital_panel.parquet")
require_input(CAPITAL_PANEL, "03_case_study_capitals/01_build_capital_panel.R")

g <- as.data.table(read_parquet(PATHS$dataset))[, .(city_id, year,
  gradient_dmsp = nl_gradient_pwc_pop_dmsp_gpw, gradient_viirs = nl_gradient_pwc_pop_viirs_gpw)]


# ------------------------------------------------------------------------------
# 1. Table 3: share of negative gradients
# ------------------------------------------------------------------------------

neg <- rbind(
  g[!is.na(gradient_dmsp), .(source = "DMSP", pct = 100 * mean(gradient_dmsp < 0), n = .N), by = year],
  g[year %in% VIIRS_YEARS & !is.na(gradient_viirs), .(source = "VIIRS", pct = 100 * mean(gradient_viirs < 0), n = .N), by = year]
)[order(source, year)]
print(neg)
save_table(neg, "table_si_pwc_negative_gradients.csv")

mini <- function(d, title) c(
  "\\begin{minipage}[t]{0.45\\textwidth}", "\\centering", paste0("\\textbf{", title, "}\\\\"), "\\vspace{4pt}",
  "\\begin{tabular}{cc}", "\\toprule", "Year & \\% Negative \\\\", "\\midrule",
  sprintf("%d & %s\\%% \\\\", d$year, num(d$pct, 1)), "\\bottomrule", "\\end{tabular}", "\\end{minipage}")
nd <- neg[source == "DMSP"]; nv <- neg[source == "VIIRS"]
writeLines(c(
  "\\begin{table}[H]", "\\centering",
  "\\caption{Percentage of negative gradient observations (with population control), population-weighted centroids}",
  "\\singlespacing",
  mini(nd, "Panel A: DMSP"), "\\hfill", mini(nv, "Panel B: VIIRS"),
  "\\begin{flushleft}",
  paste0("\\footnotesize\\textit{Note:} Proportion of city-years with negative luminosity gradients, after controlling ",
         "for population, computed over observations with estimable gradients. Distances are measured from the ",
         "population-weighted centroid of each city and year (GPW population) instead of the city centroid of the ",
         "main dataset. Gradient samples range from ", int(min(nd$n)), " (", nd$year[which.min(nd$n)], ") to ",
         int(max(nd$n)), " (", nd$year[which.max(nd$n)], ") city-years under DMSP, and VIIRS samples are ",
         int(nv$n[1]), " (", nv$year[1], ") and ", int(nv$n[2]), " (", nv$year[2], ")."),
  "\\end{flushleft}", "\\end{table}"), file.path(SI_TABLE_DIR, "table_si_pwc_negative_gradients.tex"), useBytes = TRUE)


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
save_table(cap, "table_si_pwc_capital_gradients.csv")

cap_panel <- function(d) c(
  paste0("\\begin{tabular}{l", strrep("c", nrow(d)), "}"), "\\toprule",
  paste0(" & ", paste(sprintf("\\textbf{%d}", d$year), collapse = " & "), " \\\\"), "\\midrule",
  paste0("Capital City & ", paste(coef_tex(d$estimate, d$p_value), collapse = " & "), " \\\\"),
  paste0(" & ", paste(se_tex(d$std_error), collapse = " & "), " \\\\"), "\\midrule",
  paste0("N & ", paste(d$n_obs, collapse = " & "), " \\\\"), "\\midrule",
  paste0("Country FE & ", paste(rep("X", nrow(d)), collapse = " & "), " \\\\"), "\\bottomrule", "\\end{tabular}")
writeLines(c(
  "\\begin{table}[H]", "\\centering",
  "\\caption{NL gradient in capital vs non-capital cities (by year), population-weighted centroids}",
  "\\singlespacing", "\\textbf{Panel A: DMSP}\\\\", "\\vspace{4pt}",
  "\\adjustbox{max width=\\textwidth}{", cap_panel(cap[source == "DMSP"]), "}",
  "\\vspace{10pt}", "\\\\\\textbf{Panel B: VIIRS}\\\\", "\\vspace{4pt}",
  "\\adjustbox{max width=0.4\\textwidth}{", cap_panel(cap[source == "VIIRS"]), "}",
  "\\begin{flushleft}",
  paste0("\\footnotesize\\textit{Note:} OLS regression coefficients for the capital city indicator on luminosity ",
         "gradients (with population control) measured from population-weighted centroids, estimated separately for ",
         "each year, with country fixed effects. The capital indicator and the sample are those of Table 4 of the ",
         "main article. Standard errors clustered at the country level in parentheses, computed over ",
         min(cap$n_clusters), " to ", max(cap$n_clusters), " clusters depending on the year. ", STARS_NOTE),
  "\\end{flushleft}", "\\end{table}"), file.path(SI_TABLE_DIR, "table_si_pwc_capital_gradients.tex"), useBytes = TRUE)


log_step("Supplementary tables on population-weighted centroids complete.")
