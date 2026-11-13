# ==============================================================================
# s5_build_mexico_census_inequality.R
#
# Supplementary Information, Section S5, census input (Mexico). Census-based
# inequality of household labour income for the urban centers of the epoch
# dataset.
#
# Input   DIR_CENSUS_MEXICO   INEGI census sample microdata and locality list:
#           inegi-censo2010/sas/viviendas_<EE>.sas7bdat   Censo 2010, muestra
#           inegi-intercensal2015/csv/TR_VIVIENDA<EE>.CSV  Encuesta Intercensal 2015
#           inegi-censo2020/csv/Viviendas00.CSV            Censo 2020, muestra
#           inegi-iter2020/ITER_NALCSV20.csv               ITER 2020 (locality coordinates)
#         PATH_UCDB_MTUC      epoch polygons (GHS-UCDB R2024A MTUC)
# Output  PATHS$mexico_census   one row per urban center-epoch (2010, 2015, 2020)
#
# Only this step needs the microdata. Its output is bundled in data/census_mexico/,
# so the validation table (s5_census_validation.R) runs without it.
#
# UNIT. The household (one record per dwelling), weighted by its expansion
# factor (FACTOR). Income is INGTRHOG, household income from work, available for
# households with at least one employed member; households without it are left
# out.
#
# GEOGRAPHY. The microdata identify the locality of a dwelling (LOC50K) only when
# the locality has 50,000 inhabitants or more. Each such locality is placed at its
# ITER 2020 coordinates and assigned to the urban center whose polygon of the
# census year contains it. When an urban center contains several large localities
# (metropolitan areas), their households are pooled. Urban centers without a large
# locality are not covered. The state of an urban center is that of its most
# populous large locality.
#
# EXCLUSIONS, as in the ACS case study: negative incomes and the INEGI codes for
# unspecified income (999998, 999999) in both measures, zero incomes in the Theil.
#
# Source: INEGI, Censo de Población y Vivienda 2010 and 2020 (muestra censal) and
# Encuesta Intercensal 2015. The indices are computed by the authors, not by INEGI.
# ==============================================================================

source(here::here("src", "R", "setup.R"))
source(here::here("src", "R", "inequality.R"))

library(data.table)
library(haven)
library(sf)
library(DescTools)

if (!exists("DIR_CENSUS_MEXICO") || !dir.exists(DIR_CENSUS_MEXICO)) {
  stop("Set DIR_CENSUS_MEXICO in config.R (see config.example.R). The output of this step is ",
       "bundled in data/census_mexico/, so it is only needed to rebuild that file.", call. = FALSE)
}
require_input(PATH_UCDB_MTUC)
sf_use_s2(FALSE)

CENSUS_YEARS <- c(2010, 2015, 2020)
loc_key <- function(ent, mun, loc) as.numeric(ent) * 1e7 + as.numeric(mun) * 1e4 + as.numeric(loc)


# ------------------------------------------------------------------------------
# 1. Households in large localities
# ------------------------------------------------------------------------------

read_households <- function(yr) {
  log_step("Reading INEGI households, ", yr)
  cols <- c("ENT", "MUN", "LOC50K", "FACTOR", "INGTRHOG")
  v <- switch(as.character(yr),
    "2010" = rbindlist(lapply(
      list.files(file.path(DIR_CENSUS_MEXICO, "inegi-censo2010", "sas"), "^viviendas_[0-9]{2}[.]sas7bdat$", full.names = TRUE),
      function(f) as.data.table(read_sas(f, col_select = dplyr::all_of(cols))))),
    "2015" = rbindlist(lapply(
      list.files(file.path(DIR_CENSUS_MEXICO, "inegi-intercensal2015", "csv"), "^TR_VIVIENDA[0-9]{2}[.]CSV$", full.names = TRUE),
      function(f) fread(f, select = cols, colClasses = "character"))),
    "2020" = fread(file.path(DIR_CENSUS_MEXICO, "inegi-censo2020", "csv", "Viviendas00.CSV"),
                   select = cols, colClasses = "character"))
  v <- v[LOC50K != "0000" & !is.na(LOC50K)]
  v[, .(year = yr, ent = as.integer(ENT), loc = loc_key(ENT, MUN, LOC50K), weight = as.numeric(FACTOR),
        income = suppressWarnings(as.numeric(trimws(INGTRHOG))))]
}
hh <- rbindlist(lapply(CENSUS_YEARS, read_households))
hh <- hh[!is.na(income) & income >= 0 & income < 999998]
log_step(sprintf("%s households with labour income in large localities.", format(nrow(hh), big.mark = ",")))


# ------------------------------------------------------------------------------
# 2. Large localities inside each epoch polygon
# ------------------------------------------------------------------------------

dms_to_degrees <- function(s) {
  p <- regmatches(s, regexec("([0-9]+)°([0-9]+)'([0-9.]+)\"*\\s*([NSEW])", s))
  vapply(p, function(z) if (length(z) < 5) NA_real_ else
    (as.numeric(z[2]) + as.numeric(z[3]) / 60 + as.numeric(z[4]) / 3600) * ifelse(z[5] %in% c("S", "W"), -1, 1),
    numeric(1))
}
iter <- fread(file.path(DIR_CENSUS_MEXICO, "inegi-iter2020", "ITER_NALCSV20.csv"),
              select = c("ENTIDAD", "MUN", "LOC", "LONGITUD", "LATITUD", "POBTOT"),
              colClasses = "character", encoding = "UTF-8")
iter <- iter[!LOC %in% c("0000", "9998", "9999") & MUN != "000"]
iter[, loc := loc_key(ENTIDAD, MUN, LOC)]
iter <- iter[loc %in% unique(hh$loc)]
iter[, `:=`(lon = dms_to_degrees(LONGITUD), lat = dms_to_degrees(LATITUD), pop2020 = as.numeric(POBTOT))]
log_step(sprintf("%d large localities in the microdata, %d with ITER 2020 coordinates.",
                 uniqueN(hh$loc), sum(!is.na(iter$lon))))
points <- st_as_sf(iter[!is.na(lon), .(loc, pop2020, lon, lat)], coords = c("lon", "lat"), crs = 4326)

loc_city <- rbindlist(lapply(CENSUS_YEARS, function(yr) {
  polys <- st_read(PATH_UCDB_MTUC, layer = paste0("GHSL_UCDB_MTUC_", yr, "_GLOBE_R2024"), quiet = TRUE)
  polys <- st_make_valid(st_transform(polys, 4326))
  hit <- st_join(points, polys, join = st_within)
  as.data.table(st_drop_geometry(hit))[!is.na(ID_UC_G0), .(year = yr, city_id_epoch_ucdb2024 = ID_UC_G0, loc, pop2020)]
}))


# ------------------------------------------------------------------------------
# 3. Inequality per urban center-epoch
# ------------------------------------------------------------------------------

d <- merge(loc_city, hh, by = c("year", "loc"))
mexico <- d[, .(
  state_code      = ent[which.max(pop2020)],
  n_localities    = uniqueN(loc),
  n_households    = .N,
  gini_census     = Gini(income, weights = weight, unbiased = FALSE, na.rm = TRUE),
  theil_census    = theil_weighted(income, weight)
), by = .(city_id_epoch_ucdb2024, year)][order(city_id_epoch_ucdb2024, year)]

print(mexico[, .(urban_centers = .N, multi_locality = sum(n_localities > 1)), by = year])

dir.create(dirname(PATHS$mexico_census), recursive = TRUE, showWarnings = FALSE)
fwrite(mexico, PATHS$mexico_census)
log_step("Wrote ", PATHS$mexico_census)
