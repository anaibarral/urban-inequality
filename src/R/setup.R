# ==============================================================================
# setup.R
#
# Shared configuration loader and path helpers.
#
# Every script in `src/` begins with:
#
#     source(here::here("src", "R", "setup.R"))
#
# which loads `config.R`, validates that the inputs it points at exist, and
# exposes the path helpers used throughout the pipeline.
# ==============================================================================

if (!requireNamespace("here", quietly = TRUE)) {
  stop("The 'here' package is required. Install it with install.packages('here').")
}


# ------------------------------------------------------------------------------
# Load machine-specific configuration
# ------------------------------------------------------------------------------

.config_path <- here::here("config.R")

if (!file.exists(.config_path)) {
  stop(
    "config.R not found at ", .config_path, ".\n",
    "Copy config.example.R to config.R and set the paths for your machine.",
    call. = FALSE
  )
}

source(.config_path)

for (.required in c("DIR_RAW", "DIR_CLEAN", "DIR_OUTPUT", "PATH_UCDB",
                    "DIR_NTL_DMSP", "DIR_NTL_VIIRS", "DIR_POPULATION",
                    "DIR_ACS_IPUMS", "PATH_CAPITALS", "N_CORES")) {
  if (!exists(.required)) {
    stop("config.R does not define ", .required,
         ". Compare it against config.example.R.", call. = FALSE)
  }
}


# ------------------------------------------------------------------------------
# Derived paths
# ------------------------------------------------------------------------------
# Intermediate products, in pipeline order. Steps read and write only through
# these names, so relocating the data directory is a one-line change.

PATHS <- list(
  grids            = file.path(DIR_CLEAN, "shapefiles", "city_grids.shp"),
  grid_centroids   = file.path(DIR_CLEAN, "shapefiles", "city_grids_centroids.shp"),
  distances        = file.path(DIR_CLEAN, "distances", "grid_centroid_distances.parquet"),

  cells_dmsp       = file.path(DIR_CLEAN, "cells", "cells_ntl_population_dmsp.parquet"),
  cells_viirs      = file.path(DIR_CLEAN, "cells", "cells_ntl_population_viirs.parquet"),

  gradients_pop_dmsp     = file.path(DIR_CLEAN, "gradients", "gradients_pop_control_dmsp.parquet"),
  gradients_pop_viirs    = file.path(DIR_CLEAN, "gradients", "gradients_pop_control_viirs.parquet"),
  gradients_no_pop_dmsp  = file.path(DIR_CLEAN, "gradients", "gradients_no_pop_control_dmsp.parquet"),
  gradients_no_pop_viirs = file.path(DIR_CLEAN, "gradients", "gradients_no_pop_control_viirs.parquet"),

  gini_dmsp        = file.path(DIR_CLEAN, "gini", "gini_dmsp.parquet"),
  gini_viirs       = file.path(DIR_CLEAN, "gini", "gini_viirs.parquet"),
  theil_dmsp       = file.path(DIR_CLEAN, "theil", "theil_dmsp.parquet"),
  theil_viirs      = file.path(DIR_CLEAN, "theil", "theil_viirs.parquet"),

  dataset          = file.path(DIR_CLEAN, "consolidated",
                               "urban_inequality_dataset_1995_2020.parquet"),

  # Bundled with the repository: aggregate census inequality, one row per
  # city-year. Step 1 of the ACS case study overwrites these from IPUMS
  # microdata; steps 2 and 3 read them and need nothing else.
  acs_gini         = here::here("data", "acs", "acs_gini_by_city.xlsx"),
  acs_theil        = here::here("data", "acs", "acs_theil_by_city.xlsx")
)

# `config.R` may define PATHS_OVERRIDE to redirect individual entries, for
# instance to run the exhibits against the published Parquet file downloaded
# from the Dataverse without rebuilding anything:
#
#     PATHS_OVERRIDE <- list(dataset = "C:/downloads/urban_inequality_dataset_1995_2020.parquet")
#
# Only the named entries change; everything else keeps its default location.
if (exists("PATHS_OVERRIDE")) {
  unknown <- setdiff(names(PATHS_OVERRIDE), names(PATHS))
  if (length(unknown) > 0) {
    stop("PATHS_OVERRIDE names entries that do not exist: ",
         paste(unknown, collapse = ", "), call. = FALSE)
  }
  PATHS <- utils::modifyList(PATHS, PATHS_OVERRIDE)
}


# ------------------------------------------------------------------------------
# Analysis constants
# ------------------------------------------------------------------------------

# Benchmark years. Determined by the availability of gridded population data:
# GPWv4 supplies 2000-2020 and GPWv3 supplies 1995.
BENCHMARK_YEARS <- c(1995, 2000, 2005, 2010, 2015, 2020)

# Years for which VIIRS annual composites are used. Every VIIRS quantity in the
# dataset and in the exhibits is computed over these years only; summarising a
# VIIRS variable over the full panel silently treats 1995-2010 as missing data
# rather than as out of scope.
VIIRS_YEARS <- c(2015, 2020)

# Minimum number of valid grid cells per city-year.
#   Gini and Theil need two cells to have a distribution at all.
#   The gradients need five: with an intercept, distance and population there
#   are three parameters, so five cells leave two degrees of freedom.
MIN_CELLS_DISPERSION <- 2L
MIN_CELLS_GRADIENT   <- 5L


# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

#' Create a directory if it does not exist, then return its path.
ensure_dir <- function(path) {
  if (!dir.exists(path)) dir.create(path, recursive = TRUE, showWarnings = FALSE)
  path
}

#' Path to a generated table, creating `outputs/tables/` on first use.
path_table <- function(...) file.path(ensure_dir(file.path(DIR_OUTPUT, "tables")), ...)

#' Path to a generated figure, creating `outputs/figures/` on first use.
path_figure <- function(...) file.path(ensure_dir(file.path(DIR_OUTPUT, "figures")), ...)

#' Create the parent directory of `path`, then return `path`.
#' Lets a script write to a nested location without a separate dir.create call.
prepare_output <- function(path) {
  ensure_dir(dirname(path))
  path
}

#' Stop with an informative message if an expected input is missing.
require_input <- function(path, produced_by = NULL) {
  if (!file.exists(path)) {
    stop("Required input not found: ", path,
         if (!is.null(produced_by)) paste0("\nIt is produced by ", produced_by, ".") else "",
         call. = FALSE)
  }
  invisible(path)
}

#' Extract a four-digit benchmark year from a raster file name.
#'
#' Handles the three naming conventions present in the raw inputs:
#'   DMSP-like   F15_20150101_20151231.global.stable_lights.avg_vis.tif
#'   VIIRS VNL   VNL_v21_npp_2015_global_vcmslcfg_c202205302300.average_masked.tif
#'   GPW         gpw_v4_population_density_rev11_2015_30_sec.tif
year_from_filename <- function(path) {
  fname <- basename(path)

  # DMSP: satellite tag (F12, F15, ...) immediately followed by the year.
  m <- regmatches(fname, regexec("F\\d{2}(19\\d{2}|20\\d{2})", fname))[[1]]
  if (length(m) >= 2) return(as.integer(m[2]))

  # VIIRS and GPW: a year delimited by underscores.
  m <- regmatches(fname, regexec("_(19\\d{2}|20\\d{2})_", fname))[[1]]
  if (length(m) >= 2) return(as.integer(m[2]))

  # Fallback: any bare four-digit year in the name.
  m <- regmatches(fname, regexec("(19\\d{2}|20\\d{2})", fname))[[1]]
  if (length(m) >= 2) return(as.integer(m[2]))

  NA_integer_
}

#' Map each benchmark year to exactly one raster in a directory.
#'
#' Returns a data frame with columns `year` and `path`, sorted by year.
#'
#' `list.files()` is called with `recursive = TRUE` on purpose. The rasters are
#' large and tend to accumulate in subfolders; a non-recursive listing silently
#' returns a different file set depending on how the directory happens to be
#' organised, which is enough to build the DMSP and VIIRS branches of the
#' pipeline on different population inputs without any error being raised.
#' Requiring one raster per year makes that failure loud instead.
resolve_rasters_by_year <- function(dir, years, label = basename(dir)) {
  if (!dir.exists(dir)) {
    stop("Directory not found for ", label, ": ", dir, call. = FALSE)
  }

  files <- list.files(dir, pattern = "\\.tif$|\\.tif\\.gz$",
                      full.names = TRUE, recursive = TRUE)
  if (length(files) == 0) {
    stop("No rasters found for ", label, " in ", dir, call. = FALSE)
  }

  idx <- data.frame(
    path = files,
    year = vapply(files, year_from_filename, integer(1)),
    stringsAsFactors = FALSE
  )
  idx <- idx[!is.na(idx$year) & idx$year %in% years, , drop = FALSE]

  missing <- setdiff(years, idx$year)
  if (length(missing) > 0) {
    stop("No ", label, " raster found for year(s): ",
         paste(missing, collapse = ", "), " in ", dir, call. = FALSE)
  }

  dupes <- idx$year[duplicated(idx$year)]
  if (length(dupes) > 0) {
    offending <- idx[idx$year %in% dupes, ]
    stop("More than one ", label, " raster matches year(s) ",
         paste(unique(dupes), collapse = ", "), ":\n  ",
         paste(basename(offending$path), collapse = "\n  "),
         "\nKeep exactly one raster per year so that the DMSP and VIIRS ",
         "branches are built on identical inputs.", call. = FALSE)
  }

  idx <- idx[order(idx$year), c("year", "path")]
  rownames(idx) <- NULL
  idx
}

#' Population rasters for the benchmark years.
#' Both extraction steps call this, so both see the same files by construction.
resolve_population_rasters <- function(years = BENCHMARK_YEARS) {
  resolve_rasters_by_year(DIR_POPULATION, years, label = "population")
}

#' Register a parallel backend and return the cluster, for `on.exit` teardown.
start_cluster <- function(n_cores = N_CORES) {
  cl <- parallel::makeCluster(n_cores)
  doParallel::registerDoParallel(cl)
  message(sprintf("Parallel backend registered on %d cores.", n_cores))
  cl
}

stop_cluster <- function(cl) {
  parallel::stopCluster(cl)
  foreach::registerDoSEQ()
}

#' Timestamped console message, so long parallel steps report progress.
log_step <- function(...) {
  message(sprintf("[%s] %s", format(Sys.time(), "%H:%M:%S"), paste0(...)))
}
