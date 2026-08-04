# ==============================================================================
# config.example.R
#
# Machine-specific configuration for the Urban Inequality Dataset pipeline.
#
# HOW TO USE
#   1. Copy this file to `config.R` in the repository root.
#   2. Edit the four root paths below to match your machine.
#   3. Never commit `config.R` — it is listed in .gitignore.
#
# Every script in `src/` reaches its inputs and outputs through the helpers
# defined in `src/R/setup.R`, which read the values set here. No script in this
# repository contains a hard-coded absolute path.
# ==============================================================================


# ------------------------------------------------------------------------------
# 1. Root directories
# ------------------------------------------------------------------------------

# Raw, unmodified inputs downloaded from the providers (see README.md, "Data").
DIR_RAW <- "C:/path/to/project/data/raw"

# Intermediate and final derived data written by the pipeline.
DIR_CLEAN <- "C:/path/to/project/data/clean"

# Tables and figures that reproduce the exhibits of the paper.
DIR_OUTPUT <- file.path(getwd(), "outputs")


# ------------------------------------------------------------------------------
# 2. Raw input files
# ------------------------------------------------------------------------------
# Paths are given relative to DIR_RAW. Adjust only if your folder layout
# differs from the one documented in README.md.

# GHS Urban Centre Database R2019A (GeoPackage).
PATH_UCDB <- file.path(DIR_RAW, "ghsl",
                       "GHS_STAT_UCDB2015MT_GLOBE_R2019A_V1_2.gpkg")

# Directory of extended DMSP-like annual composites (one GeoTIFF per year).
DIR_NTL_DMSP <- file.path(DIR_RAW, "ntl", "dmsp_annual")

# Directory of VIIRS VNL v2.1 annual composites (one GeoTIFF per year).
DIR_NTL_VIIRS <- file.path(DIR_RAW, "ntl", "viirs_annual")

# Directory of gridded population density rasters, one per benchmark year.
#
# IMPORTANT: the pipeline reads this directory with `list.files(recursive =
# TRUE)`, and every benchmark year must resolve to exactly one raster. Both the
# DMSP and the VIIRS extraction steps must see the same set of files, otherwise
# the two sources are built on different population inputs. `src/R/setup.R`
# enforces this with `resolve_population_rasters()`.
DIR_POPULATION <- file.path(DIR_RAW, "population")

# IPUMS USA extracts for the ACS case study: one .xml DDI file per ACS sample,
# with the matching .dat.gz alongside it.
#
# Needed ONLY by 04_case_study_acs/01_compute_acs_inequality.R. Its output is
# bundled in data/acs/, so the rest of the case study runs without it. IPUMS
# terms forbid redistributing extracts; see data/README.md to rebuild them.
DIR_ACS_IPUMS <- file.path(DIR_RAW, "acs_usa_ipums")

# Reference list of national capitals (CountryName, CapitalName, ...).
# Bundled with the repository.
PATH_CAPITALS <- here::here("data", "reference", "country-capitals.csv")


# ------------------------------------------------------------------------------
# 3. Compute
# ------------------------------------------------------------------------------

# Cores used by the parallel steps. Leave at least two free for the OS.
N_CORES <- max(1L, parallel::detectCores() - 2L)
