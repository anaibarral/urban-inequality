# ==============================================================================
# config.example.R
#
# Machine-specific configuration for the Urban Inequality Dataset pipeline.
#
# HOW TO USE
#   1. Copy this file to `config.R` in the repository root.
#   2. Edit the root paths below to match your machine.
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

# Directory of VIIRS VNL v2.1 annual composites. The folder may hold several
# products per year; the pipeline reads the one named in VIIRS_PRODUCT
# (src/R/setup.R).
DIR_NTL_VIIRS <- file.path(DIR_RAW, "ntl", "viirs_annual")

# Directory of gridded population COUNT rasters (persons per cell), one per
# benchmark year: GPWv4 Rev. 11 population count at 30 arc-seconds for
# 2000-2020, and the GPWv3 UN-adjusted population count grid (glp95ag, 2.5
# arc-minutes) for 1995.
#
# IMPORTANT: the pipeline reads this directory with `list.files(recursive =
# TRUE)`, and every benchmark year must resolve to exactly one raster. Both the
# DMSP and the VIIRS extraction steps must see the same set of files, otherwise
# the two sources are built on different population inputs. `src/R/setup.R`
# enforces this with `resolve_population_rasters()`.
DIR_POPULATION <- file.path(DIR_RAW, "population")

# GHS-POP R2023A population count rasters, one per benchmark year.
#   DIR_GHS_POP       30 arc-second WGS84 version (EPSG:4326), used for the
#                     second population total of the main dataset.
#   DIR_GHS_POP_MOLL  1 km Mollweide version (ESRI:54009), the grid of the
#                     GHS-UCDB R2024A polygons, used by the epoch dataset.
DIR_GHS_POP      <- file.path(DIR_RAW, "ghs_pop", "wgs84_30ss")
DIR_GHS_POP_MOLL <- file.path(DIR_RAW, "ghs_pop", "mollweide_1km")

# GHS Urban Centre Database R2024A, used by the epoch dataset
# (src/05_epoch_dataset/).
#   PATH_UCDB_MTUC  multitemporal urban centres: one polygon layer per epoch.
#   PATH_UCDB_2024  full database, read for the national capital indicator.
PATH_UCDB_MTUC <- file.path(DIR_RAW, "ghsl", "GHS_UCDB_MTUC_GLOBE_R2024A.gpkg")
PATH_UCDB_2024 <- file.path(DIR_RAW, "ghsl", "GHS_UCDB_GLOBE_R2024A.gpkg")

# IPUMS USA extracts for the ACS case study: one .xml DDI file per ACS sample,
# with the matching .dat.gz alongside it.
#
# Needed ONLY by 04_case_study_acs/01_compute_acs_inequality.R. Its output is
# bundled in data/acs/, so the rest of the case study runs without it. IPUMS
# terms forbid redistributing extracts; see data/README.md to rebuild them.
DIR_ACS_IPUMS <- file.path(DIR_RAW, "acs_usa_ipums")

# Census microdata for the supplementary validation with Mexico and Brazil
# (src/06_supplementary/). Needed ONLY by s5_build_mexico_census_inequality.R and
# s5_build_brazil_census_inequality.R; their
# outputs are bundled in data/census_mexico/ and data/census_brazil/. Expected
# layout (see data/README.md for the download links):
#   DIR_CENSUS_MEXICO/inegi-censo2010/sas/viviendas_<EE>.sas7bdat
#   DIR_CENSUS_MEXICO/inegi-intercensal2015/csv/TR_VIVIENDA<EE>.CSV
#   DIR_CENSUS_MEXICO/inegi-censo2020/csv/Viviendas00.CSV
#   DIR_CENSUS_MEXICO/inegi-iter2020/ITER_NALCSV20.csv
#   DIR_CENSUS_BRAZIL/ibge-censo2000/<UF>.zip, DIR_CENSUS_BRAZIL/ibge-censo2010/<UF>.zip
#   DIR_CENSUS_BRAZIL/geobr-brasil/  (municipal boundaries; downloaded if absent)
DIR_CENSUS_MEXICO <- file.path(DIR_RAW, "census_mexico")
DIR_CENSUS_BRAZIL <- file.path(DIR_RAW, "census_brazil")

# US census tracts (src/06_supplementary/s4_build_us_tract_inequality.R, only to
# rebuild data/census_us_tracts/): needs a free Census Data API key
# (https://api.census.gov/data/key_signup.html) in the environment variable
# CENSUS_API_KEY, for instance in ~/.Renviron. Do not write the key here.

# Reference list of national capitals (CountryName, CapitalName, ...).
# Bundled with the repository.
PATH_CAPITALS <- here::here("data", "reference", "country-capitals.csv")


# ------------------------------------------------------------------------------
# 3. Compute
# ------------------------------------------------------------------------------

# Cores used by the parallel steps. Leave at least two free for the OS.
N_CORES <- max(1L, parallel::detectCores() - 2L)
