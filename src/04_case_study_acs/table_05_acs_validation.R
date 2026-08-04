# ==============================================================================
# table_05_acs_validation.R
#
# Case study 2, step 3. Reproduces TABLE 5 of the paper, "Regression Analysis:
# Satellite-based Inequality vs. Census Data (Panel Data)", Panel A (DMSP,
# N = 420) and Panel B (VIIRS, N = 116).
#
# Input   <DIR_CLEAN>/case_studies/acs_matched_{dmsp,viirs}.parquet
#           (04_case_study_acs/02_match_acs_to_urban_centres.R)
# Output  outputs/tables/table_05_acs_validation.csv
#         outputs/tables/table_a01_acs_validation_logs.csv
#         outputs/figures/figure_a05_acs_vs_ntl_{gini,theil}.png
#
# THE SPECIFICATION. For each measure M in {Gini, Theil} and each NTL source,
#
#     ACS^M_it = alpha + beta * NTL^M_it + delta_t + gamma_s(i) + e_it
#
# with year fixed effects delta_t and state fixed effects gamma_s(i), and
# standard errors clustered at the city level. The three columns per measure are
# no fixed effects, year only, and state plus year.
#
# LEVELS ARE THE REPORTED SPECIFICATION. Table 5 of the paper reports the levels
# regressions, so those are built first and written as Table 5. The log-log
# specification is estimated as well and written separately as an appendix
# table: it answers a different question (elasticity rather than slope) and is
# not what the manuscript tabulates.
# ==============================================================================

source(here::here("src", "R", "setup.R"))
source(here::here("src", "R", "plotting.R"))

library(dplyr)
library(purrr)
library(fixest)
library(broom)
library(arrow)
library(ggplot2)
library(patchwork)

DIR_CASE <- file.path(DIR_CLEAN, "case_studies")
matched <- list(
  DMSP  = file.path(DIR_CASE, "acs_matched_dmsp.parquet"),
  VIIRS = file.path(DIR_CASE, "acs_matched_viirs.parquet")
)
walk(matched, require_input, "04_case_study_acs/02_match_acs_to_urban_centres.R")

samples <- map(matched, read_parquet)


# ------------------------------------------------------------------------------
# 1. Estimate
# ------------------------------------------------------------------------------

#' Three fixed-effect specifications for one outcome/regressor pair.
estimate_trio <- function(data, outcome, regressor, transform = c("levels", "logs")) {
  transform <- match.arg(transform)

  wrap <- function(v) if (transform == "logs") paste0("log(", v, ")") else v
  lhs <- wrap(outcome)
  rhs <- wrap(regressor)

  list(
    `(1) No FE`           = feols(as.formula(sprintf("%s ~ %s", lhs, rhs)),
                                  data = data, cluster = ~ city_id),
    `(2) Year FE`         = feols(as.formula(sprintf("%s ~ %s | year", lhs, rhs)),
                                  data = data, cluster = ~ city_id),
    `(3) State + Year FE` = feols(as.formula(sprintf("%s ~ %s | state_code + year", lhs, rhs)),
                                  data = data, cluster = ~ city_id)
  )
}

#' Tidy one trio into table rows.
collect_trio <- function(models, source, measure, transform) {
  imap_dfr(models, function(model, spec) {
    coefs <- tidy(model)
    row <- coefs[!grepl("Intercept", coefs$term), ][1, ]
    tibble(
      source        = source,
      measure       = measure,
      transform     = transform,
      specification = spec,
      term          = row$term,
      estimate      = row$estimate,
      std_error     = row$std.error,
      p_value       = row$p.value,
      n_obs         = nobs(model),
      r_squared     = fixest::r2(model, "r2"),
      within_r2     = tryCatch(unname(fixest::r2(model, "wr2")), error = function(e) NA_real_)
    )
  })
}

pairs <- tribble(
  ~source, ~measure, ~outcome,    ~regressor_suffix,
  "DMSP",  "Gini",   "gini_acs",  "gini_nl_dmsp",
  "DMSP",  "Theil",  "theil_acs", "theil_nl_dmsp",
  "VIIRS", "Gini",   "gini_acs",  "gini_nl_viirs",
  "VIIRS", "Theil",  "theil_acs", "theil_nl_viirs"
)

results <- pmap_dfr(pairs, function(source, measure, outcome, regressor_suffix) {
  data <- samples[[source]]
  map_dfr(c("levels", "logs"), function(transform) {
    models <- estimate_trio(data, outcome, regressor_suffix, transform)
    log_step(sprintf("%s %s (%s): %d observations.",
                     source, measure, transform, nobs(models[[1]])))
    collect_trio(models, source, measure, transform)
  })
})


# ------------------------------------------------------------------------------
# 2. Format
# ------------------------------------------------------------------------------

stars <- function(p) case_when(p < 0.01 ~ "***", p < 0.05 ~ "**", p < 0.10 ~ "*", TRUE ~ "")

format_table <- function(df) {
  df |>
    transmute(
      source, measure, specification,
      coefficient = sprintf("%.3f%s", estimate, stars(p_value)),
      std_error   = sprintf("(%.3f)", std_error),
      n_obs,
      r_squared   = round(r_squared, 3),
      within_r2   = round(within_r2, 3)
    ) |>
    arrange(source, measure, specification)
}

table_05     <- format_table(filter(results, transform == "levels"))
table_a01    <- format_table(filter(results, transform == "logs"))

cat("\n=== TABLE 5: satellite-based inequality vs census data (levels) ===\n")
for (src in c("DMSP", "VIIRS")) {
  n <- unique(filter(results, source == src, transform == "levels")$n_obs)
  cat(sprintf("\nPanel %s: %s (N = %s)\n",
              if (src == "DMSP") "A" else "B", src, paste(n, collapse = "/")))
  table_05 |> filter(source == src) |> select(-source) |>
    as.data.frame() |> print(row.names = FALSE)
}
cat("\n*** p < 0.01; ** p < 0.05; * p < 0.1. Standard errors clustered by city.\n")

save_table(table_05, "table_05_acs_validation.csv")

cat("\n=== APPENDIX: log-log specification ===\n")
save_table(table_a01, "table_a01_acs_validation_logs.csv")


# ------------------------------------------------------------------------------
# 3. Scatterplots
# ------------------------------------------------------------------------------
# The regression coefficients summarise a slope; these show the underlying
# relationship, which is what a reader wants when judging construct validity.

acs_scatter <- function(data, x, y, x_lab, y_lab, title) {
  r <- cor.test(data[[x]], data[[y]])
  ggplot(data, aes(x = .data[[x]], y = .data[[y]])) +
    geom_point(colour = PAL$point, size = 2, alpha = 0.6) +
    geom_smooth(method = "lm", formula = y ~ x, colour = "firebrick",
                se = TRUE, fill = "pink", alpha = 0.2) +
    labs(
      title    = title,
      subtitle = sprintf("r = %.3f, p = %.4f, N = %d",
                         r$estimate, r$p.value, sum(complete.cases(data[c(x, y)]))),
      x = x_lab, y = y_lab
    ) +
    theme_urban()
}

for (measure in c("gini", "theil")) {
  panels <- map(c("DMSP", "VIIRS"), function(src) {
    column <- sprintf("%s_nl_%s", measure, tolower(src))
    acs_scatter(
      samples[[src]], column, paste0(measure, "_acs"),
      sprintf("%s, nighttime lights (%s)", toupper(measure), src),
      sprintf("%s, ACS", toupper(measure)),
      sprintf("%s: satellite vs census (%s)", toupper(measure), src)
    )
  })

  save_figure(panels[[1]] + panels[[2]],
              sprintf("figure_a05_acs_vs_ntl_%s.png", measure),
              width = 12, height = 5)
}

log_step("Table 5 complete.")
