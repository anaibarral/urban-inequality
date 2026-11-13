# ==============================================================================
# table_si_dmsp_topcoding.R
#
# Supplementary Information, Section S6: does DMSP top-coding (cells at the
# maximum digital number, DN = 63) lower measured inequality in the brightest
# cities? In the years with both sources (2015 and 2020), the VIIRS - DMSP
# difference in each index is related to the share of top-coded DMSP cells.
#
#   - binned scatter of the difference against the share of top-coded cells,
#     with two linear fits (figure)
#   - regressions with controls, year and country fixed effects, in three
#     samples: all cities, cities with top-coded cells, and cities with
#     top-coded cells without the 0.5% most top-coded city-years of each year
#     (table)
#
# Main dataset (GHS-UCDB R2019A 2015 polygons), GPW population.
#
# Input   PATHS$cells_dmsp, PATHS$cells_viirs   (01_data_construction step 3)
#         PATHS$dataset                         (01_data_construction step 6)
# Output  outputs/tables/table_si_topcoding_regressions.csv
#         outputs/tables/supplementary/table_si_topcoding_regressions.tex
#         outputs/figures/supplementary/figure_si_topcoding_share.pdf
#
# City-level variables, over the cells with positive population (the sample of
# the Gini):
#   share_sat   share of cells with DMSP = 63
#   share_zero  share of cells with DMSP = 0 (light not detected by DMSP), control
#   log_cells   log of the number of cells, control
# Standard errors clustered by country.
# ==============================================================================

source(here::here("src", "R", "setup.R"))
source(here::here("src", "R", "plotting.R"))
source(here::here("src", "06_supplementary", "latex.R"))

library(data.table)
library(arrow)
library(fixest)
library(ggplot2)
library(patchwork)

require_input(PATHS$cells_dmsp, "01_data_construction/03_extract_ntl_and_population.R")
require_input(PATHS$cells_viirs, "01_data_construction/03_extract_ntl_and_population.R")
require_input(PATHS$dataset, "01_data_construction/06_consolidate_dataset.R")

DMSP_MAX   <- 63
TOP_SHARE <- 0.005   # share of city-years excluded from the third sample, per year
                     # (round(0.005 * N), N = all cities of the year: 63 per year)


# ------------------------------------------------------------------------------
# 1. City-year variables
# ------------------------------------------------------------------------------

dm <- as.data.table(read_parquet(PATHS$cells_dmsp))[year %in% VIIRS_YEARS]
vi <- as.data.table(read_parquet(PATHS$cells_viirs))
cells <- merge(dm[, .(city_id, year, grid_cell_id, pop, dmsp = nl_measure)],
               vi[, .(city_id, year, grid_cell_id, viirs = nl_measure)],
               by = c("city_id", "year", "grid_cell_id"))
rm(dm, vi); gc()
cells <- cells[pop > 0 & !is.na(dmsp) & !is.na(viirs)]
city <- cells[, .(share_sat = mean(dmsp >= DMSP_MAX), share_zero = mean(dmsp == 0),
                  n_cells_pop = .N), by = .(city_id, year)]

ds <- as.data.table(read_parquet(PATHS$dataset))[year %in% VIIRS_YEARS,
  .(city_id, year, iso_code, gini_dmsp = nl_gini_coef_dmsp_gpw, gini_viirs = nl_gini_coef_viirs_gpw,
    theil_dmsp = nl_theil_coef_dmsp_gpw, theil_viirs = nl_theil_coef_viirs_gpw)]
x <- merge(ds, city, by = c("city_id", "year"))
x[, `:=`(d_gini = gini_viirs - gini_dmsp, d_theil = theil_viirs - theil_dmsp,
         log_cells = log(n_cells_pop), any_sat = as.integer(share_sat > 0))]


# ------------------------------------------------------------------------------
# 2. Samples
# ------------------------------------------------------------------------------
#   x        all cities
#   x_sat    cities with top-coded cells
#   x_top    x_sat without the round(TOP_SHARE * N) city-years with the highest
#            share of top-coded cells in each year, where N is the number of
#            all cities of the year (ties broken by city_id)

n_top <- x[, .(n_drop = round(TOP_SHARE * .N)), by = year]
x_sat <- x[any_sat == 1]
x_top <- merge(copy(x_sat), n_top, by = "year")[order(year, -share_sat, city_id)]
x_top <- x_top[, rk := seq_len(.N), by = year][rk > n_drop][, c("rk", "n_drop") := NULL][]
log_step(sprintf("Excluding the top %.1f%%: %d city-years (%s per year).", 100 * TOP_SHARE,
                 sum(n_top$n_drop), paste(unique(n_top$n_drop), collapse = " and ")))


# ------------------------------------------------------------------------------
# 3. Binned scatter
# ------------------------------------------------------------------------------
# Year means are removed from y (adding back the grand mean). Cities without
# top-coded cells form one point at x = 0, and the cities with top-coded cells
# are split into ten bins with 10% of them each (ties broken at random). Two
# linear fits: over all city-years, and over the sample of the third column of
# the table (x_top). Both lines are drawn over the range of the plotted points.

demean_year <- function(z, yr) z - ave(z, yr, FUN = function(a) mean(a, na.rm = TRUE)) + mean(z, na.rm = TRUE)
LINE_ALL <- "All city-years"
LINE_SAT <- "Excl. cities with no top-coding and the top 0.5% most top-coded"

binned <- function(y) {
  s <- x[!is.na(get(y)), .(city_id, year, yy = get(y), xx = share_sat)]
  s[, yr := demean_year(yy, year)]
  set.seed(20261112)
  s[, bin := 0]
  s[xx > 0, bin := ceiling(10 * frank(xx, ties.method = "random") / .N)]
  s2 <- s[paste(city_id, year) %in% x_top[, paste(city_id, year)]]
  pts <- s[, .(x = mean(xx), y = mean(yr)), by = bin]
  f_all <- coef(lm(yr ~ xx, s))
  f_sat <- coef(lm(yr ~ xx, s2))
  list(points = pts,
       fits = rbind(data.table(line = LINE_ALL, x0 = 0, x1 = max(pts$x), a = f_all[[1]], b = f_all[[2]]),
                    data.table(line = LINE_SAT, x0 = min(pts[bin > 0]$x), x1 = max(pts$x), a = f_sat[[1]], b = f_sat[[2]])))
}

panel_plot <- function(y, ylab) {
  b <- binned(y)
  ggplot() +
    geom_segment(data = b$fits, aes(x = x0, xend = x1, y = a + b * x0, yend = a + b * x1, colour = line),
                 linewidth = 0.7) +
    geom_point(data = b$points, aes(x, y), size = 2.4, colour = "#1f4e79") +
    scale_colour_manual(values = setNames(c("#c0392b", "#e69f00"), c(LINE_ALL, LINE_SAT)), name = NULL) +
    labs(x = "Share of DMSP cells top-coded (DN = 63)", y = ylab) +
    theme_minimal(base_size = 11) +
    theme(panel.grid.minor = element_blank(), legend.position = "bottom")
}

fig <- (panel_plot("d_gini", "Gini VIIRS − Gini DMSP") | panel_plot("d_theil", "Theil VIIRS − Theil DMSP")) +
  plot_layout(guides = "collect") & theme(legend.position = "bottom")
ggsave(file.path(SI_FIGURE_DIR, "figure_si_topcoding_share.pdf"), fig, width = 10, height = 4.8, device = cairo_pdf)


# ------------------------------------------------------------------------------
# 4. Regressions
# ------------------------------------------------------------------------------

fit <- function(y, data) {
  feols(as.formula(paste(y, "~ share_sat + log_cells + share_zero | year + iso_code")),
        data, cluster = ~iso_code, notes = FALSE, warn = FALSE)
}
models <- list(fit("d_gini", x), fit("d_gini", x_sat), fit("d_gini", x_top),
               fit("d_theil", x), fit("d_theil", x_sat), fit("d_theil", x_top))

# Only the coefficient on the share of top-coded cells is reported; the controls
# are listed in the note.
LABELS <- c(share_sat = "Share of DMSP cells top-coded")
SAMPLE_HEAD <- c("All cities", "\\shortstack{Excl.\\ cities with\\\\no top-coding}",
                 "\\shortstack{Excl.\\ cities with\\\\no top-coding\\\\and top 0.5\\%}")

rows <- unlist(lapply(names(LABELS), function(tm) {
  est <- sapply(models, function(m) coef(m)[[tm]])
  p   <- sapply(models, function(m) pvalue(m)[[tm]])
  se_ <- sapply(models, function(m) se(m)[[tm]])
  c(paste0(LABELS[[tm]], " & ", paste(coef_tex(est, p), collapse = " & "), " \\\\"),
    paste0(" & ", paste(se_tex(se_), collapse = " & "), " \\\\"))
}))

body <- c(
  "\\toprule",
  " & \\multicolumn{3}{c}{Gini VIIRS $-$ Gini DMSP} & \\multicolumn{3}{c}{Theil VIIRS $-$ Theil DMSP} \\\\",
  " \\cmidrule(lr){2-4} \\cmidrule(lr){5-7}",
  paste0(" & ", paste(rep(SAMPLE_HEAD, 2), collapse = " & "), " \\\\"),
  paste0(" & ", paste(sprintf("(%d)", 1:6), collapse = " & "), " \\\\"),
  "\\midrule",
  rows,
  "\\midrule",
  paste0("Controls & ", paste(rep("Yes", 6), collapse = " & "), " \\\\"),
  paste0("Year FE & ", paste(rep("Yes", 6), collapse = " & "), " \\\\"),
  paste0("Country FE & ", paste(rep("Yes", 6), collapse = " & "), " \\\\"),
  paste0("Observations & ", paste(int(sapply(models, nobs)), collapse = " & "), " \\\\"),
  paste0("$R^2$ within & ", paste(num(sapply(models, function(m) fitstat(m, "wr2")[[1]])), collapse = " & "), " \\\\"),
  "\\bottomrule")

write_si_table(
  "table_si_topcoding_regressions.tex",
  "VIIRS $-$ DMSP difference and share of top-coded DMSP cells",
  "lcccccc", body,
  paste0("Each observation is a city in 2015 or 2020. The dependent variable is the VIIRS index minus the DMSP ",
         "index. Controls: log number of cells and share of DMSP cells at zero. Columns 2, 3, 5 and 6 exclude the ",
         "city-years without top-coded cells. Columns 3 and 6 also exclude the 0.5\\% of city-years with the ",
         "highest share of top-coded cells in each year (", sum(n_top$n_drop), " city-years, ",
         paste(unique(n_top$n_drop), collapse = " and "), " per year). Standard errors clustered by country in ",
         "parentheses. ", STARS_NOTE),
  size = "\\footnotesize", fit = TRUE)

coefs <- data.table::rbindlist(lapply(seq_along(models), function(i) {
  m <- models[[i]]
  data.table::data.table(column = i, index = rep(c("gini", "theil"), each = 3)[i],
                         sample = rep(c("all", "top_coded", "top_coded_excl_top_0.5pct"), 2)[i],
                         term = names(coef(m)), estimate = coef(m), std_error = se(m), p_value = pvalue(m),
                         n_obs = nobs(m), r2_within = fitstat(m, "wr2")[[1]])
}))
print(coefs[term == "share_sat"])
save_table(coefs, "table_si_topcoding_regressions.csv")

log_step("Supplementary table and figure on DMSP top-coding complete.")
