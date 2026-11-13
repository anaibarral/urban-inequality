# ==============================================================================
# 00_run_all.R
#
# Master script. Runs the pipeline end to end, then reproduces every computed
# exhibit of the paper in the order the exhibits appear.
#
#     Rscript src/00_run_all.R              # everything
#     Rscript src/00_run_all.R exhibits     # exhibits only, dataset already built
#     Rscript src/00_run_all.R dataset      # dataset only
#     Rscript src/00_run_all.R epoch        # epoch dataset and its validation
#     Rscript src/00_run_all.R supplementary  # Supplementary Information tables and figures
#
# Requires config.R in the repository root. See config.example.R.
#
# RUNTIME. The full pipeline takes many hours: step 1 builds ~920,000 grid
# polygons, step 3 extracts eight global raster pairs, and step 4 fits roughly
# 175,000 city-year regressions. Steps write their outputs to disk, so a failed
# run can be resumed by invoking the remaining scripts directly rather than
# restarting from step 1.
# ==============================================================================

stage <- commandArgs(trailingOnly = TRUE)
stage <- if (length(stage) == 0) "all" else stage[1]

if (!stage %in% c("all", "dataset", "exhibits", "epoch", "supplementary")) {
  stop("Unknown stage '", stage, "'. Use one of: all, dataset, exhibits, epoch, supplementary.",
       call. = FALSE)
}

source(here::here("src", "R", "setup.R"))


# ------------------------------------------------------------------------------
# Script inventory
# ------------------------------------------------------------------------------
# Order matters: each entry consumes the output of the ones above it.

DATASET_SCRIPTS <- c(
  "src/01_data_construction/01_build_urban_centre_grids.R",
  "src/01_data_construction/02_compute_grid_distances.R",
  "src/01_data_construction/03_extract_ntl_and_population.R",
  "src/01_data_construction/04_estimate_gradients.R",
  "src/01_data_construction/04b_estimate_gradients_pwc.R",
  "src/01_data_construction/05_compute_dispersion_indices.R",
  "src/01_data_construction/06_consolidate_dataset.R"
)

# Listed in the order the exhibits appear in the manuscript. The two case
# studies each build their own analysis panel before their table.
EXHIBIT_SCRIPTS <- c(
  # Table 2
  "src/02_validation/table_02_data_quality.R",
  # Figure 2
  "src/02_validation/figure_02_gradient_distributions.R",
  # Table 3
  "src/02_validation/table_03_negative_gradients.R",
  # Table 4
  "src/03_case_study_capitals/01_build_capital_panel.R",
  "src/03_case_study_capitals/table_04_capital_gradients.R",
  # Table 5
  "src/04_case_study_acs/01_compute_acs_inequality.R",
  "src/04_case_study_acs/02_match_acs_to_urban_centres.R",
  "src/04_case_study_acs/table_05_acs_validation.R",
  # Table 6
  "src/02_validation/table_06_pairwise_correlations.R"
)

# The epoch dataset: GHS-UCDB R2024A polygons of each epoch, with its own
# validation tables. Independent of the main dataset except for the crosswalk.
EPOCH_SCRIPTS <- c(
  "src/05_epoch_dataset/01_population_centroids.R",
  "src/05_epoch_dataset/02_grid_distances.R",
  "src/05_epoch_dataset/03_extract_ntl_and_population.R",
  "src/05_epoch_dataset/04_compute_metrics.R",
  "src/05_epoch_dataset/05_consolidate_dataset.R",
  "src/05_epoch_dataset/table_e_validation_epoch.R"
)

# Supplementary Information: all its tables and figures. Needs the main
# and the epoch datasets. Steps 01 and 02 of the folder (census microdata) are
# not run here: their outputs are bundled in data/census_mexico/ and
# data/census_brazil/. Step 03 (US census tracts, needs a Census Data API key)
# is not run either: its output is bundled in data/census_us_tracts/.
SUPPLEMENTARY_SCRIPTS <- c(
  "src/06_supplementary/table_si_ghspop.R",
  "src/06_supplementary/table_si_pwc_gradients.R",
  "src/06_supplementary/table_si_epoch_validation.R",
  "src/06_supplementary/table_si_census_validation.R",
  "src/06_supplementary/table_si_dmsp_topcoding.R",
  "src/06_supplementary/table_si_tract_validation.R"
)

scripts <- switch(
  stage,
  all      = c(DATASET_SCRIPTS, EXHIBIT_SCRIPTS, EPOCH_SCRIPTS, SUPPLEMENTARY_SCRIPTS),
  dataset  = DATASET_SCRIPTS,
  exhibits = EXHIBIT_SCRIPTS,
  epoch    = EPOCH_SCRIPTS,
  supplementary = SUPPLEMENTARY_SCRIPTS
)


# ------------------------------------------------------------------------------
# Run
# ------------------------------------------------------------------------------
# Each script runs in its own environment so that objects do not leak between
# steps: a script that accidentally relies on a variable left behind by an
# earlier one would work here and fail when run on its own.

log_step(sprintf("Stage '%s': %d script(s) to run.", stage, length(scripts)))
started_at <- Sys.time()

for (i in seq_along(scripts)) {
  path <- here::here(scripts[i])

  if (!file.exists(path)) {
    stop("Script not found: ", path, call. = FALSE)
  }

  message("\n", strrep("=", 78))
  message(sprintf("[%d/%d] %s", i, length(scripts), scripts[i]))
  message(strrep("=", 78))

  step_started <- Sys.time()
  source(path, local = new.env(), echo = FALSE)
  message(sprintf("--- finished in %s",
                  format(round(difftime(Sys.time(), step_started), 1))))
}

message("\n", strrep("=", 78))
log_step(sprintf("Stage '%s' complete in %s.", stage,
                 format(round(difftime(Sys.time(), started_at), 1))))
message("Tables: ", file.path(DIR_OUTPUT, "tables"))
message("Figures: ", file.path(DIR_OUTPUT, "figures"))
message(strrep("=", 78))
