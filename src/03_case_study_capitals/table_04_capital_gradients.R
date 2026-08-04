# ==============================================================================
# table_04_capital_gradients.R
#
# Case study 1, step 2. Reproduces TABLE 4 of the paper, "NL Gradient in Capital
# vs Non-Capital Cities (by year)", Panel A (DMSP) and Panel B (VIIRS).
#
# Input   <DIR_CLEAN>/case_studies/capital_panel.parquet  (01_build_capital_panel.R)
# Output  outputs/tables/table_04_capital_gradients.csv
#         outputs/figures/figure_a03_capital_coefficients_{dmsp,viirs}.png
#         outputs/figures/figure_a04_capital_gradient_densities_{dmsp,viirs}.png
#
# THE SPECIFICATION. For each benchmark year and NTL source, separately,
#
#     beta_i = alpha + theta * Capital_i + gamma_c(i) + e_i
#
# where beta_i is the population-controlled gradient of city i, Capital_i is the
# indicator, and gamma_c(i) are country fixed effects. theta therefore compares
# capitals with other cities IN THE SAME COUNTRY, which is the point: capitals
# sit in richer and more electrified countries on average, so a raw comparison
# would mostly recover cross-country differences.
#
# STANDARD ERRORS. Table 4 reports conventional (i.i.d.) standard errors, and
# the reported column here is i.i.d. so that the two agree exactly. The 1995
# DMSP cell is the reference point: 0.0190, the 0.019 printed in the manuscript.
#
# `feols(y ~ capital | country_name)` with no vcov argument returns i.i.d.
# errors, not cluster-by-first-fixed-effect. That is what produced the published
# numbers, and it is now stated explicitly through `vcov = "iid"` rather than
# left to a default that is easy to misread.
#
# The country-clustered errors are computed alongside and written to the same
# CSV, because they are the natural robustness check: cities within a country
# share shocks to electrification, reporting and grid coverage. Clustering
# widens the errors by roughly a third. Every coefficient stays negative and
# significant at 5%, and two of eight cells move from *** to ** (DMSP 1995 and
# 2010). The note under Table 4 in the manuscript says as much.
#
#   se_iid         reported, and printed in Table 4
#   se_clustered   robustness, reported in the CSV and in the console summary
#
# WHY N IS SMALLER THAN THE COUNT OF ESTIMABLE GRADIENTS. Countries represented
# by a single urban centre carry no within-country variation and are absorbed
# entirely by the fixed effect. fixest drops those singleton observations, which
# is correct and is why the paper's note explains the gap.
# ==============================================================================

source(here::here("src", "R", "setup.R"))
source(here::here("src", "R", "plotting.R"))

library(dplyr)
library(tidyr)
library(purrr)
library(fixest)
library(broom)
library(arrow)
library(ggplot2)

PANEL <- file.path(DIR_CLEAN, "case_studies", "capital_panel.parquet")
require_input(PANEL, "03_case_study_capitals/01_build_capital_panel.R")

panel <- read_parquet(PANEL)


# ------------------------------------------------------------------------------
# 1. Estimate, year by year
# ------------------------------------------------------------------------------

#' Fit the capital-premium regression for every year of one gradient column,
#' under both variance estimators. See the header note.
fit_by_year <- function(frame, outcome) {
  formula <- as.formula(paste0(outcome, " ~ capital | country_name"))

  frame |>
    drop_na(all_of(outcome), capital, country_name) |>
    split(~ year) |>
    map(function(d) list(
      clustered = feols(formula, data = d, cluster = ~ country_name, notes = FALSE),
      iid       = feols(formula, data = d, vcov = "iid", notes = FALSE)
    ))
}

#' Extract the capital coefficient under both estimators into one row.
tidy_both <- function(pair) {
  clustered <- coeftable(pair$clustered)["capital", ]
  iid       <- coeftable(pair$iid)["capital", ]
  ci        <- confint(pair$clustered)["capital", ]

  tibble(
    estimate      = clustered[["Estimate"]],
    se_clustered  = clustered[["Std. Error"]],
    p_clustered   = clustered[["Pr(>|t|)"]],
    se_iid        = iid[["Std. Error"]],
    p_iid         = iid[["Pr(>|t|)"]],
    conf.low      = ci[[1]],
    conf.high     = ci[[2]],
    n_obs         = nobs(pair$clustered)
  )
}

specifications <- tribble(
  ~source,  ~outcome,                   ~years,           ~specification,
  "DMSP",   "nl_gradient_pop_dmsp",     BENCHMARK_YEARS,  "With population control",
  "VIIRS",  "nl_gradient_pop_viirs",    VIIRS_YEARS,      "With population control",
  "DMSP",   "nl_gradient_no_pop_dmsp",  BENCHMARK_YEARS,  "Without population control",
  "VIIRS",  "nl_gradient_no_pop_viirs", VIIRS_YEARS,      "Without population control"
)

stars <- function(p) {
  case_when(p < 0.01 ~ "***", p < 0.05 ~ "**", p < 0.10 ~ "*", TRUE ~ "")
}

results <- pmap_dfr(specifications, function(source, outcome, years, specification) {
  frame  <- filter(panel, year %in% years)
  models <- fit_by_year(frame, outcome)

  log_step(sprintf("%s, %s: fitted %d yearly regressions.",
                   source, tolower(specification), length(models)))

  map_dfr(models, tidy_both, .id = "year") |>
    mutate(
      source            = source,
      specification     = specification,
      year              = as.integer(year),
      stars_clustered   = stars(p_clustered),
      stars_iid         = stars(p_iid),
      .before = 1
    )
})


# ------------------------------------------------------------------------------
# 2. Table 4
# ------------------------------------------------------------------------------

table_04 <- results |>
  transmute(
    source, specification, year,
    coefficient  = sprintf("%.3f%s", estimate, stars_iid),
    std_error    = sprintf("(%.3f)", se_iid),
    se_clustered_robustness = sprintf("(%.3f)", se_clustered),
    stars_clustered_robustness = stars_clustered,
    conf_low    = round(conf.low, 4),
    conf_high   = round(conf.high, 4),
    n_obs,
    country_fe  = "X"
  ) |>
  arrange(desc(specification), source, year)

cat("\n=== TABLE 4: capital vs non-capital gradients ===\n")
for (src in c("DMSP", "VIIRS")) {
  cat(sprintf("\nPanel %s: %s, with population control\n",
              if (src == "DMSP") "A" else "B", src))
  table_04 |>
    filter(source == src, specification == "With population control") |>
    select(year, coefficient, std_error, n_obs, country_fe) |>
    as.data.frame() |> print(row.names = FALSE)
}

cat("\n*** p < 0.01; ** p < 0.05; * p < 0.1.\n")
cat("Conventional (i.i.d.) standard errors, as reported in Table 4.\n")

cat("\n--- Robustness: clustering by country ---\n")
cat(sprintf("Median SE inflation: %.2fx | still significant at 5%%: %d of %d | all negative: %s\n",
            median(results$se_clustered / results$se_iid),
            sum(results$p_clustered < 0.05), nrow(results),
            all(results$estimate < 0)))

changed <- results |> filter(stars_clustered != stars_iid)
if (nrow(changed) > 0) {
  cat(sprintf("%d of %d cells change significance tier:\n", nrow(changed), nrow(results)))
  changed |>
    select(source, specification, year, estimate, stars_iid, stars_clustered) |>
    as.data.frame() |> print(row.names = FALSE)
}

save_table(table_04, "table_04_capital_gradients.csv")


# ------------------------------------------------------------------------------
# 3. Coefficient plots
# ------------------------------------------------------------------------------
# The capital premium over time, with 95% intervals. Supports the paper's
# observation that the effect attenuates across the study period.

for (src in c("DMSP", "VIIRS")) {
  plot_data <- results |>
    filter(source == src, specification == "With population control")

  p <- ggplot(plot_data, aes(x = year, y = estimate)) +
    geom_point(size = 3, colour = "black") +
    geom_errorbar(aes(ymin = conf.low, ymax = conf.high), width = 0.2) +
    geom_hline(yintercept = 0, linetype = "dashed", colour = PAL$reference) +
    scale_x_continuous(breaks = plot_data$year) +
    labs(x = "\nYear", y = "Estimated effect on NL gradient\n") +
    theme_urban()

  save_figure(p, sprintf("figure_a03_capital_coefficients_%s.png", tolower(src)))
}


# ------------------------------------------------------------------------------
# 4. Distribution of gradients by capital status
# ------------------------------------------------------------------------------
# Within-country residuals, so the picture matches the regression: each city's
# gradient minus its country mean. Countries with a single city are dropped,
# exactly as the fixed effect drops them.

residual_density <- function(frame, column, x_limits = c(-0.5, 0.5)) {
  frame |>
    drop_na(all_of(column)) |>
    group_by(country_name) |>
    filter(n() > 1) |>
    mutate(
      residual = .data[[column]] - mean(.data[[column]], na.rm = TRUE),
      status   = if_else(capital == 1, "Capital city", "Non-capital city")
    ) |>
    ungroup() |>
    ggplot(aes(x = residual, fill = status, colour = status)) +
    geom_density(alpha = 0.4) +
    geom_vline(xintercept = 0, linetype = "dashed", colour = "gray40", linewidth = 0.8) +
    xlim(x_limits[1], x_limits[2]) +
    scale_fill_manual(values  = c("Capital city" = PAL$capital,
                                  "Non-capital city" = PAL$other)) +
    scale_colour_manual(values = c("Capital city" = PAL$capital,
                                   "Non-capital city" = PAL$other)) +
    labs(x = "Residuals", y = "Density", fill = "City type", colour = "City type") +
    theme_urban()
}

# Restricted to countries that actually contain a matched capital, since a
# country with no capital in the sample contributes only to one of the two
# densities and would tilt the comparison.
final_year <- max(BENCHMARK_YEARS)

for (src in c("dmsp", "viirs")) {
  column <- paste0("nl_gradient_pop_", src)

  frame <- panel |>
    filter(year == final_year) |>
    group_by(country_name) |>
    filter(any(capital == 1)) |>
    ungroup()

  save_figure(residual_density(frame, column),
              sprintf("figure_a04_capital_gradient_densities_%s.png", src))
}

log_step("Table 4 complete.")
