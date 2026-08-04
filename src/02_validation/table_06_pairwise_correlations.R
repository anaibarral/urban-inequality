# ==============================================================================
# table_06_pairwise_correlations.R
#
# Reproduces TABLE 6 of the paper, "Pairwise correlations between inequality
# measures", all three panels:
#
#   Panel A  within-source correlations, DMSP, all benchmark years
#   Panel B  within-source correlations, VIIRS, 2015-2020
#   Panel C  the same measure computed from DMSP and from VIIRS, 2015-2020
#
# Input   PATHS$dataset   (01_data_construction/06_consolidate_dataset.R)
# Output  outputs/tables/table_06_pairwise_correlations.csv
#         outputs/figures/figure_a02_measure_scatterplots_{dmsp,viirs}.png
#
# THE SAMPLE FOR PANEL A. Columns are selected before dropping missing values.
# Selecting the DMSP columns first leaves the full 1995-2020 panel; dropping
# missing values across all columns at once would require a VIIRS value to be
# present too, silently restricting Panel A to 2015 and 2020 and making it a
# second copy of Panel B on a different sample.
# ==============================================================================

source(here::here("src", "R", "setup.R"))
source(here::here("src", "R", "plotting.R"))

library(dplyr)
library(tidyr)
library(arrow)
library(ggplot2)
library(patchwork)

require_input(PATHS$dataset, "01_data_construction/06_consolidate_dataset.R")

dataset <- read_parquet(PATHS$dataset)

MEASURE_LABELS <- c("Gini", "Theil", "Gradient (pop control)")


# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

significance_stars <- function(p) {
  dplyr::case_when(p < 0.01 ~ "***", p < 0.05 ~ "**", p < 0.10 ~ "*", TRUE ~ "")
}

#' Lower-triangle correlation matrix with significance stars.
#' The upper triangle is left blank: it is the same information by symmetry.
correlation_panel <- function(frame, vars, labels) {
  n <- length(vars)
  out <- matrix("", nrow = n, ncol = n, dimnames = list(labels, labels))

  for (i in seq_len(n)) {
    for (j in seq_len(n)) {
      if (i == j) {
        out[i, j] <- "1.000"
      } else if (i > j) {
        test <- cor.test(frame[[vars[i]]], frame[[vars[j]]], use = "complete.obs")
        out[i, j] <- paste0(sprintf("%.3f", test$estimate), significance_stars(test$p.value))
      }
    }
  }

  as.data.frame(out) |> tibble::rownames_to_column("Measure")
}


# ------------------------------------------------------------------------------
# Panel A: DMSP
# ------------------------------------------------------------------------------

dmsp_vars <- c("nl_gini_coef_dmsp", "nl_theil_coef_dmsp", "nl_gradient_pop_dmsp")

df_dmsp <- dataset |> select(all_of(dmsp_vars)) |> drop_na()
panel_a <- correlation_panel(df_dmsp, dmsp_vars, MEASURE_LABELS)

cat(sprintf("\n=== Panel A: DMSP pairwise correlations (N = %s) ===\n",
            format(nrow(df_dmsp), big.mark = ",")))
print(panel_a, row.names = FALSE)


# ------------------------------------------------------------------------------
# Panel B: VIIRS
# ------------------------------------------------------------------------------

viirs_vars <- c("nl_gini_coef_viirs", "nl_theil_coef_viirs", "nl_gradient_pop_viirs")

df_viirs <- dataset |>
  filter(year %in% VIIRS_YEARS) |>
  select(all_of(viirs_vars)) |>
  drop_na()
panel_b <- correlation_panel(df_viirs, viirs_vars, MEASURE_LABELS)

cat(sprintf("\n=== Panel B: VIIRS pairwise correlations (N = %s; %s) ===\n",
            format(nrow(df_viirs), big.mark = ","),
            paste(range(VIIRS_YEARS), collapse = "-")))
print(panel_b, row.names = FALSE)


# ------------------------------------------------------------------------------
# Panel C: cross-source agreement
# ------------------------------------------------------------------------------
# The same measure computed from the two sensors over the overlapping years.
# High values indicate that a measure is robust to the choice of NTL input.

cross_source <- tibble::tibble(
  measure = MEASURE_LABELS,
  dmsp    = dmsp_vars,
  viirs   = viirs_vars
) |>
  rowwise() |>
  mutate(
    n = sum(complete.cases(dataset[dataset$year %in% VIIRS_YEARS, c(dmsp, viirs)])),
    r = {
      sub <- dataset[dataset$year %in% VIIRS_YEARS, c(dmsp, viirs)]
      sub <- sub[complete.cases(sub), ]
      cor(sub[[1]], sub[[2]])
    },
    p = {
      sub <- dataset[dataset$year %in% VIIRS_YEARS, c(dmsp, viirs)]
      sub <- sub[complete.cases(sub), ]
      cor.test(sub[[1]], sub[[2]])$p.value
    }
  ) |>
  ungroup() |>
  mutate(correlation = paste0(sprintf("%.3f", r), significance_stars(p))) |>
  select(measure, correlation, n)

cat("\n=== Panel C: same measure, DMSP vs VIIRS (2015-2020) ===\n")
print(as.data.frame(cross_source), row.names = FALSE)


# ------------------------------------------------------------------------------
# Assemble Table 6
# ------------------------------------------------------------------------------

table_06 <- bind_rows(
  panel_a |> mutate(Panel = sprintf("Panel A: DMSP (N = %s)",
                                    format(nrow(df_dmsp), big.mark = ",")), .before = 1),
  panel_b |> mutate(Panel = sprintf("Panel B: VIIRS (N = %s; %s)",
                                    format(nrow(df_viirs), big.mark = ","),
                                    paste(range(VIIRS_YEARS), collapse = "-")), .before = 1),
  cross_source |>
    transmute(
      Panel   = "Panel C: Cross-source (DMSP vs VIIRS, 2015-2020)",
      Measure = measure,
      Gini    = correlation,
      Theil   = "",
      `Gradient (pop control)` = ""
    )
)

save_table(table_06, "table_06_pairwise_correlations.csv")


# ------------------------------------------------------------------------------
# Supporting scatterplots
# ------------------------------------------------------------------------------
# Not an exhibit of the paper; kept because the correlation coefficients alone
# do not reveal whether a relationship is linear.

scatter <- function(frame, x, y, x_lab, y_lab) {
  r <- round(cor(frame[[x]], frame[[y]], use = "complete.obs"), 3)
  ggplot(frame, aes(x = .data[[x]], y = .data[[y]])) +
    geom_point(alpha = 0.2, colour = PAL$interval, size = 0.7) +
    geom_smooth(method = "lm", formula = y ~ x, colour = "firebrick", linewidth = 0.5) +
    labs(title = paste(x_lab, "vs", y_lab), subtitle = paste("Corr:", r),
         x = x_lab, y = y_lab) +
    theme_urban()
}

for (src in c("dmsp", "viirs")) {
  vars <- if (src == "dmsp") dmsp_vars else viirs_vars
  frame <- if (src == "dmsp") dataset else filter(dataset, year %in% VIIRS_YEARS)
  tag <- toupper(src)

  panel <- (scatter(frame, vars[1], vars[2], paste("Gini", tag), paste("Theil", tag)) +
            scatter(frame, vars[1], vars[3], paste("Gini", tag), paste("Gradient", tag)) +
            scatter(frame, vars[2], vars[3], paste("Theil", tag), paste("Gradient", tag)))

  save_figure(panel, sprintf("figure_a02_measure_scatterplots_%s.png", src),
              width = 14, height = 6)
}

log_step("Table 6 complete.")
