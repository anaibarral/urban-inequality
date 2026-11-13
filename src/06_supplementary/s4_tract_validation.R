# ==============================================================================
# s4_tract_validation.R
#
# Supplementary Information, Section S4: census-based income inequality between
# census tracts of US urban centres against nightlights inequality.
#
#   Panel A  nightlights Gini and Theil of the main dataset (between 1 km cells)
#   Panel B  nightlights Gini and Theil between the same census tracts
#
# Eight columns per panel: Gini and Theil x DMSP (2010, 2015, 2020) and VIIRS
# (2015, 2020) x no fixed effects and state plus year fixed effects. One
# observation per urban centre and year, standard errors clustered by urban
# centre.
#
# Input   PATHS$us_tract_inequality   (bundled, s4_build_us_tract_inequality.R)
#         PATHS$dataset               (01_data_construction step 6)
# Output  outputs/tables/table_si_tract_validation.csv
#         outputs/tables/supplementary/table_si_tract_validation.tex
# ==============================================================================

source(here::here("src", "R", "setup.R"))
source(here::here("src", "R", "plotting.R"))
source(here::here("src", "06_supplementary", "latex.R"))

library(data.table)
library(arrow)
library(fixest)

require_input(PATHS$us_tract_inequality, "06_supplementary/s4_build_us_tract_inequality.R")
require_input(PATHS$dataset, "01_data_construction/06_consolidate_dataset.R")

tr <- fread(PATHS$us_tract_inequality)
ds <- as.data.table(read_parquet(PATHS$dataset))[, .(city_id, year,
  gini_nl_pixel_dmsp = nl_gini_coef_dmsp_gpw, theil_nl_pixel_dmsp = nl_theil_coef_dmsp_gpw,
  gini_nl_pixel_viirs = nl_gini_coef_viirs_gpw, theil_nl_pixel_viirs = nl_theil_coef_viirs_gpw)]
city <- merge(tr, ds, by = c("city_id", "year"), all.x = TRUE)

DMSP_YRS  <- c(2010, 2015, 2020)
VIIRS_YRS <- c(2015, 2020)

fit <- function(y, xv, yrs, fe) {
  d <- city[year %in% yrs & is.finite(get(y)) & is.finite(get(xv))]
  d[, x := get(xv)]
  f <- if (fe) as.formula(paste(y, "~ x | state_code + year")) else as.formula(paste(y, "~ x"))
  feols(f, d, cluster = ~city_id, notes = FALSE)
}
panel_models <- function(kind) {
  nl <- function(idx, src) sprintf("%s_nl_%s_%s", idx, kind, src)
  list(fit("gini_inc_tract",  nl("gini", "dmsp"),   DMSP_YRS, FALSE),  fit("gini_inc_tract",  nl("gini", "dmsp"),   DMSP_YRS, TRUE),
       fit("gini_inc_tract",  nl("gini", "viirs"),  VIIRS_YRS, FALSE), fit("gini_inc_tract",  nl("gini", "viirs"),  VIIRS_YRS, TRUE),
       fit("theil_inc_tract", nl("theil", "dmsp"),  DMSP_YRS, FALSE),  fit("theil_inc_tract", nl("theil", "dmsp"),  DMSP_YRS, TRUE),
       fit("theil_inc_tract", nl("theil", "viirs"), VIIRS_YRS, FALSE), fit("theil_inc_tract", nl("theil", "viirs"), VIIRS_YRS, TRUE))
}
models <- list(A = panel_models("pixel"), B = panel_models("tract"))

panel_rows <- function(ms, title, lab_gini, lab_theil) {
  b <- sapply(ms, function(m) coef(m)[["x"]]); p <- sapply(ms, function(m) pvalue(m)[["x"]]); s <- sapply(ms, function(m) se(m)[["x"]])
  cells <- coef_tex(b, p); ses <- se_tex(s); blank <- rep("", 4)
  c(sprintf("\\multicolumn{9}{l}{\\textbf{%s}} \\\\", title), "\\addlinespace",
    paste(lab_gini,  "&", paste(c(cells[1:4], blank), collapse = " & "), "\\\\"),
    paste(" &",            paste(c(ses[1:4],   blank), collapse = " & "), "\\\\"),
    paste(lab_theil, "&", paste(c(blank, cells[5:8]), collapse = " & "), "\\\\"),
    paste(" &",            paste(c(blank, ses[5:8]),   collapse = " & "), "\\\\"),
    "\\addlinespace",
    paste("Observations &", paste(int(sapply(ms, nobs)), collapse = " & "), "\\\\"),
    paste("$R^2$ &", paste(num(sapply(ms, function(m) r2(m, "r2"))), collapse = " & "), "\\\\"),
    paste("Year FE &",  paste(rep(c("No", "Yes"), 4), collapse = " & "), "\\\\"),
    paste("State FE &", paste(rep(c("No", "Yes"), 4), collapse = " & "), "\\\\"))
}

body <- c(
  "\\toprule",
  " & \\multicolumn{4}{c}{ACS Gini (Census Tract)} & \\multicolumn{4}{c}{ACS Theil (Census Tract)} \\\\",
  "\\cmidrule(lr){2-5} \\cmidrule(lr){6-9}",
  " & \\multicolumn{2}{c}{DMSP} & \\multicolumn{2}{c}{VIIRS} & \\multicolumn{2}{c}{DMSP} & \\multicolumn{2}{c}{VIIRS} \\\\",
  "\\cmidrule(lr){2-3} \\cmidrule(lr){4-5} \\cmidrule(lr){6-7} \\cmidrule(lr){8-9}",
  paste(" &", paste(sprintf("(%d)", 1:8), collapse = " & "), "\\\\"),
  "\\midrule",
  panel_rows(models$A, "Panel A: Urban Inequality Dataset",
             "Nightlights Gini (dataset, 1 km cells)", "Nightlights Theil (dataset, 1 km cells)"),
  "\\midrule",
  panel_rows(models$B, "Panel B: Census tract nightlights",
             "Nightlights Gini (Census Tract)", "Nightlights Theil (Census Tract)"),
  "\\bottomrule")

write_si_table(
  "table_si_tract_validation.tex",
  "Census-based inequality between census tracts vs.\\ nightlights inequality, U.S.\\ urban centers",
  "lcccccccc", body,
  paste0("One observation per urban center and year. Dependent variable: Gini or Theil index of per-capita income ",
         "between the census tracts of the urban center (ACS 5-year detailed tables, tracts assigned by their interior ",
         "point), weighted by tract population. Panel A: nightlights Gini or Theil index of the dataset, computed between ",
         "the 1 km cells of the urban center. Panel B: Gini or Theil index of per-capita lights between the same tracts, ",
         "weighted by tract population. DMSP: 2010, 2015 and 2020. VIIRS: 2015 and 2020. Standard errors clustered by ",
         "urban center in parentheses. ", STARS_NOTE),
  size = "\\footnotesize\\setlength{\\tabcolsep}{3.5pt}", fit = TRUE)

coefs <- rbindlist(lapply(names(models), function(pn) rbindlist(lapply(seq_along(models[[pn]]), function(i) {
  m <- models[[pn]][[i]]
  data.table(panel = pn, column = i, index = rep(c("gini", "theil"), each = 4)[i],
             source = rep(rep(c("dmsp", "viirs"), each = 2), 2)[i], state_year_fe = rep(c(FALSE, TRUE), 4)[i],
             estimate = coef(m)[["x"]], std_error = se(m)[["x"]], p_value = pvalue(m)[["x"]],
             n_obs = nobs(m), r2 = r2(m, "r2"))
}))))
print(coefs)
save_table(coefs, "table_si_tract_validation.csv")

log_step("Supplementary table on census tract validation complete.")
