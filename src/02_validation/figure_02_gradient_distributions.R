# ==============================================================================
# figure_02_gradient_distributions.R
#
# Reproduces FIGURE 2 of the paper, "Distribution of luminosity gradients by
# year", as two panels: (a) DMSP, 1995-2020, and (b) VIIRS, 2015-2020.
#
# Input   PATHS$dataset                       (06_consolidate_dataset.R)
#         PATHS$gradients_{pop,no_pop}_{dmsp,viirs}   for confidence intervals
# Output  outputs/figures/figure_02a_gradients_pop_dmsp.png
#         outputs/figures/figure_02b_gradients_pop_viirs.png
#         plus the unconditional-gradient counterparts, for the appendix
#
# WHAT THE PANELS SHOW. Each panel is one benchmark year. Cities are sorted
# along the horizontal axis by their estimated gradient, each plotted as a point
# with its 95% confidence interval, against a dashed red line at zero. Reading
# left to right therefore traces the whole cross-sectional distribution of
# gradients, and the share of the curve lying below zero is the quantity
# tabulated in Table 3.
#
# Confidence intervals are taken from the gradient table of the SAME
# specification being plotted. This matters: the population-controlled and
# unconditional regressions have different standard errors, so pairing
# population-controlled point estimates with unconditional intervals draws bars
# that do not belong to the plotted coefficients.
# ==============================================================================

source(here::here("src", "R", "setup.R"))
source(here::here("src", "R", "plotting.R"))

library(dplyr)
library(arrow)
library(ggplot2)
library(patchwork)
library(purrr)

require_input(PATHS$dataset, "01_data_construction/06_consolidate_dataset.R")

dataset <- read_parquet(PATHS$dataset)


# ------------------------------------------------------------------------------
# Panel builder
# ------------------------------------------------------------------------------

#' One year's ranked gradient plot.
gradient_panel_year <- function(df_year, column) {
  ggplot(df_year, aes(x = reorder(city_id, .data[[column]]), y = .data[[column]])) +
    geom_point(colour = PAL$point, alpha = 0.1, size = 0.8) +
    geom_errorbar(aes(ymin = ci_low1, ymax = ci_high1),
                  alpha = 0.05, colour = PAL$interval) +
    geom_hline(yintercept = 0, colour = PAL$reference, linetype = "dashed") +
    coord_cartesian(ylim = c(-1.5, 1.5)) +
    labs(title = unique(df_year$year)) +
    theme_urban() +
    theme(
      axis.title.x = element_blank(), axis.text.x = element_blank(),
      axis.ticks.x = element_blank(), panel.grid.major.x = element_blank(),
      axis.title.y = element_blank()
    )
}

#' Assemble every benchmark year of one specification into a faceted figure.
build_gradient_figure <- function(column, gradient_path, n_col) {
  require_input(gradient_path, "01_data_construction/04_estimate_gradients.R")

  intervals <- read_parquet(gradient_path) |>
    select(city_id, year, ci_low1, ci_high1)

  panels <- dataset |>
    select(city_id, year, all_of(column)) |>
    filter(!is.na(.data[[column]])) |>
    left_join(intervals, by = c("city_id", "year")) |>
    group_split(year) |>
    map(~ gradient_panel_year(.x, column))

  wrap_plots(panels, ncol = n_col) &
    theme(plot.margin = margin(10, 10, 10, 10))
}


# ------------------------------------------------------------------------------
# Figure 2 — the population-controlled gradient, as reported in the paper
# ------------------------------------------------------------------------------

log_step("Building Figure 2(a): DMSP, population-controlled gradients.")
fig_2a <- build_gradient_figure("nl_gradient_pop_dmsp", PATHS$gradients_pop_dmsp, n_col = 3)
save_figure(fig_2a, "figure_02a_gradients_pop_dmsp.png", width = 10, height = 6)

log_step("Building Figure 2(b): VIIRS, population-controlled gradients.")
fig_2b <- build_gradient_figure("nl_gradient_pop_viirs", PATHS$gradients_pop_viirs, n_col = 2)
save_figure(fig_2b, "figure_02b_gradients_pop_viirs.png", width = 10, height = 6)


# ------------------------------------------------------------------------------
# Unconditional counterparts, for the appendix
# ------------------------------------------------------------------------------

log_step("Building the unconditional-gradient counterparts.")

save_figure(
  build_gradient_figure("nl_gradient_no_pop_dmsp", PATHS$gradients_no_pop_dmsp, n_col = 3),
  "figure_a01a_gradients_no_pop_dmsp.png", width = 10, height = 6
)
save_figure(
  build_gradient_figure("nl_gradient_no_pop_viirs", PATHS$gradients_no_pop_viirs, n_col = 2),
  "figure_a01b_gradients_no_pop_viirs.png", width = 10, height = 6
)

log_step("Figure 2 complete.")
