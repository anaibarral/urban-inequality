# ==============================================================================
# 02_brazil_census_inequality.R
#
# Supplementary validation, step 2 (Brazil). Census-based inequality of total
# household income by municipality, and the municipality assigned to each urban
# center of the epoch dataset.
#
# Input   DIR_CENSUS_BRAZIL   IBGE census sample microdata (household records) and
#                             municipal boundaries:
#           ibge-censo2000/<UF>.zip   Censo Demográfico 2000, amostra (Dom<UF>.txt)
#           ibge-censo2010/<UF>.zip   Censo Demográfico 2010, amostra (Amostra_Domicilios_<UF>.txt)
#           geobr-brasil/municipalities_<year>.gpkg   IBGE boundaries via the geobr package;
#                             downloaded with geobr::read_municipality() when absent
#         PATH_UCDB_MTUC      epoch polygons (GHS-UCDB R2024A MTUC)
# Output  PATHS$brazil_census     one row per municipality and census year
#         PATHS$brazil_crosswalk  one row per urban center-epoch (2000, 2010)
#
# Only this step needs the microdata and the boundaries. Both outputs are bundled
# in data/census_brazil/, so the validation table runs without them.
#
# UNIT. The private household (domicílio particular), weighted by its sample
# weight. Income is total monthly household income from all sources (2010: V6529,
# 2000: V7616). Negative incomes are excluded from both measures and zero incomes
# from the Theil, as in the ACS case study.
#
# GEOGRAPHY. The finest unit identified for every household in both censuses is
# the municipality. Each urban center is assigned, in each census year, the
# municipality that covers the largest share of its polygon of that epoch
# (areas in Mollweide). The state is the first two digits of the municipal code.
#
# Source: IBGE, Censo Demográfico 2000 and 2010, microdados da amostra. The
# indices are computed by the authors, not by IBGE.
# ==============================================================================

source(here::here("src", "R", "setup.R"))
source(here::here("src", "R", "inequality.R"))

library(data.table)
library(readr)
library(sf)
library(DescTools)

if (!exists("DIR_CENSUS_BRAZIL") || !dir.exists(DIR_CENSUS_BRAZIL)) {
  stop("Set DIR_CENSUS_BRAZIL in config.R (see config.example.R). The outputs of this step are ",
       "bundled in data/census_brazil/, so it is only needed to rebuild them.", call. = FALSE)
}
require_input(PATH_UCDB_MTUC)
sf_use_s2(FALSE)

CENSUS_YEARS <- c(2000, 2010)


# ------------------------------------------------------------------------------
# 1. Households of the census samples
# ------------------------------------------------------------------------------
# Fixed-width layouts of the household files (IBGE documentation):
#   2010  UF 1-2, municipality 3-7, weight 29-44 (13 implied decimals),
#         species 54-55 (01, 02 = private), income 109-115
#   2000  UF 1-2, municipality 12-18 (7-digit code), species 72 (1, 2 = private),
#         income 145-150, weight 157-167 (8 implied decimals)

LAYOUTS <- list(
  `2010` = list(pattern = "Amostra_Domicilios_[0-9]+[^/]*[.]txt$",
                pos = fwf_positions(c(1, 3, 29, 54, 109), c(2, 7, 44, 55, 115),
                                    c("uf", "mun", "weight", "species", "income")),
                weight_div = 1e13, private = c("01", "02")),
  `2000` = list(pattern = "(^|/)Dom[0-9]+[.]txt$",
                pos = fwf_positions(c(1, 12, 72, 145, 157), c(2, 18, 72, 150, 167),
                                    c("uf", "mun", "species", "income", "weight")),
                weight_div = 1e8, private = c("1", "2"))
)

read_households <- function(yr) {
  log_step("Reading IBGE households, ", yr)
  L <- LAYOUTS[[as.character(yr)]]
  zips <- list.files(file.path(DIR_CENSUS_BRAZIL, sprintf("ibge-censo%d", yr)), "^[A-Z]{2}[A-Z0-9_]*[.]zip$",
                     full.names = TRUE)
  zips <- zips[!grepl("Documenta", zips)]
  tmp <- file.path(tempdir(), paste0("ibge", yr))
  dir.create(tmp, showWarnings = FALSE)
  # Each household file is read once: the 2000 archive of RN also contains the
  # file of PB, which has its own archive.
  seen <- character(0)
  h <- rbindlist(lapply(zips, function(z) {
    f <- grep(L$pattern, unzip(z, list = TRUE)$Name, value = TRUE, ignore.case = TRUE)
    f <- f[!toupper(basename(f)) %in% seen]
    seen <<- c(seen, toupper(basename(f)))
    if (length(f) == 0) return(NULL)
    unzip(z, files = f, exdir = tmp, junkpaths = TRUE)
    d <- rbindlist(lapply(file.path(tmp, basename(f)), function(ff)
      as.data.table(read_fwf(ff, L$pos, col_types = cols(.default = "c"), progress = FALSE))))
    file.remove(file.path(tmp, basename(f)))
    d
  }))
  h[, .(year = yr,
        code_muni = if (yr == 2010) as.integer(uf) * 100000L + as.integer(mun) else as.integer(mun),
        weight = as.numeric(weight) / L$weight_div,
        income = suppressWarnings(as.numeric(income)),
        private = trimws(species) %in% L$private)]
}
hh <- rbindlist(lapply(CENSUS_YEARS, read_households))
hh <- hh[private & !is.na(income) & income >= 0]


# ------------------------------------------------------------------------------
# 2. Inequality per municipality
# ------------------------------------------------------------------------------

brazil <- hh[, .(
  n_households = .N,
  gini_census  = Gini(income, weights = weight, unbiased = FALSE, na.rm = TRUE),
  theil_census = theil_weighted(income, weight)
), by = .(code_muni, year)][order(code_muni, year)]
log_step(sprintf("Municipal inequality: %s municipality-years.", format(nrow(brazil), big.mark = ",")))


# ------------------------------------------------------------------------------
# 3. Municipality covering the largest share of each epoch polygon
# ------------------------------------------------------------------------------

municipalities <- function(yr) {
  f <- file.path(DIR_CENSUS_BRAZIL, "geobr-brasil", sprintf("municipalities_%d.gpkg", yr))
  if (!file.exists(f)) {
    dir.create(dirname(f), recursive = TRUE, showWarnings = FALSE)
    st_write(geobr::read_municipality(year = yr, showProgress = FALSE), f, quiet = TRUE)
  }
  st_read(f, quiet = TRUE)
}

crosswalk <- rbindlist(lapply(CENSUS_YEARS, function(yr) {
  m <- st_make_valid(st_transform(municipalities(yr)[, "code_muni"], "ESRI:54009"))
  polys <- st_read(PATH_UCDB_MTUC, layer = paste0("GHSL_UCDB_MTUC_", yr, "_GLOBE_R2024"), quiet = TRUE)
  polys <- st_make_valid(st_transform(polys, "ESRI:54009"))
  polys <- polys[lengths(st_intersects(polys, st_union(m))) > 0, ]
  polys$area_uc <- as.numeric(st_area(polys))
  ii <- suppressWarnings(st_intersection(polys, m))
  data.table(year = yr, city_id_epoch_ucdb2024 = ii$ID_UC_G0, code_muni = as.integer(ii$code_muni),
             share_of_polygon = as.numeric(st_area(ii)) / ii$area_uc)
}))
crosswalk <- crosswalk[order(year, city_id_epoch_ucdb2024, -share_of_polygon)][
  , .SD[1], by = .(year, city_id_epoch_ucdb2024)]
crosswalk[, `:=`(state_code = code_muni %/% 100000L, share_of_polygon = round(share_of_polygon, 4))]
setcolorder(crosswalk, c("city_id_epoch_ucdb2024", "year", "code_muni", "state_code", "share_of_polygon"))
print(crosswalk[, .(urban_centers = .N, median_share = median(share_of_polygon)), by = year])

dir.create(dirname(PATHS$brazil_census), recursive = TRUE, showWarnings = FALSE)
fwrite(brazil, PATHS$brazil_census)
fwrite(crosswalk[order(city_id_epoch_ucdb2024, year)], PATHS$brazil_crosswalk)
log_step("Wrote ", PATHS$brazil_census, " and ", PATHS$brazil_crosswalk)
