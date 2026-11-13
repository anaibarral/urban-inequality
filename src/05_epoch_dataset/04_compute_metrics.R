# ==============================================================================
# 04_compute_metrics.R
#
# Epoch dataset, step 4 of 5. Gradients, Gini and Theil for every urban
# centre-epoch, with each NTL source (DMSP, VIIRS) and each population source
# (GPW, GHS-POP).
#
# Input   PATHS$epoch_cells       (step 3)
#         PATHS$epoch_distances   (step 2)
# Output  PATHS$epoch_metrics
#           city_id, year, and one column per metric, source and population:
#           nl_gradient_{no_pop,pop}_{dmsp,viirs}_{gpw,ghs},
#           nl_gini_coef_{dmsp,viirs}_{gpw,ghs}, nl_theil_coef_{dmsp,viirs}_{gpw,ghs}
#
# The estimators and their admissibility rules are those of the main dataset
# (src/R/inequality.R), so the two datasets differ only in their polygons, grid
# and city centre.
# ==============================================================================

source(here::here("src", "R", "setup.R"))
source(here::here("src", "R", "inequality.R"))

library(dplyr)
library(tidyr)
library(fixest)
library(DescTools)
library(arrow)
library(foreach)
library(doParallel)

require_input(PATHS$epoch_cells, "05_epoch_dataset/03_extract_ntl_and_population.R")
require_input(PATHS$epoch_distances, "05_epoch_dataset/02_grid_distances.R")

cells <- read_parquet(PATHS$epoch_cells) |>
  dplyr::left_join(read_parquet(PATHS$epoch_distances), by = c("city_id", "year", "grid_cell_id"))

cl <- start_cluster()
on.exit(stop_cluster(cl), add = TRUE)

combinations <- tidyr::expand_grid(source = c("dmsp", "viirs"), population = c("gpw", "ghs"))
tables <- list()

for (i in seq_len(nrow(combinations))) {
  src <- combinations$source[i]
  pp  <- combinations$population[i]
  sfx <- paste0("_", src, "_", pp)
  log_step(sprintf("=== %s lights, %s population ===", toupper(src), toupper(pp)))

  input <- cells |>
    dplyr::filter(if (src == "viirs") year %in% VIIRS_YEARS else TRUE) |>
    dplyr::transmute(city_id, year, grid_cell_id, dist_mt,
                     nl_measure = .data[[paste0("nl_", src)]], pop = .data[[paste0("pop_", pp)]])

  pop_control <- compute_gradients(input, population_control = TRUE)
  no_control  <- compute_gradients(input, population_control = FALSE)

  gini  <- compute_dispersion_index(input, index = "gini") |>
    dplyr::mutate(nl_gini_coef = pmax(nl_gini_coef, 0))
  theil <- compute_dispersion_index(input, index = "theil")
  stopifnot(all(theil$nl_theil_coef >= 0))

  tables[[length(tables) + 1]] <- Reduce(
    function(a, b) dplyr::full_join(a, b, by = c("city_id", "year")),
    list(
      dplyr::select(no_control,  city_id, year, !!paste0("nl_gradient_no_pop", sfx) := beta_1),
      dplyr::select(pop_control, city_id, year, !!paste0("nl_gradient_pop", sfx)    := beta_1),
      dplyr::select(gini,  city_id, year, !!paste0("nl_gini_coef", sfx)  := nl_gini_coef),
      dplyr::select(theil, city_id, year, !!paste0("nl_theil_coef", sfx) := nl_theil_coef)
    ))
}

metrics <- Reduce(function(a, b) dplyr::full_join(a, b, by = c("city_id", "year")), tables) |>
  dplyr::arrange(city_id, year)

log_step(sprintf("Metrics for %s urban centre-epochs.", format(nrow(metrics), big.mark = ",")))
print(colSums(!is.na(dplyr::select(metrics, -city_id, -year))))

write_parquet(metrics, prepare_output(PATHS$epoch_metrics))
log_step("Wrote ", PATHS$epoch_metrics)
