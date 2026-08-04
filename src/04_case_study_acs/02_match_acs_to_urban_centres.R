# ==============================================================================
# 02_match_acs_to_urban_centres.R
#
# Case study 2, step 2. Links census-based inequality to the satellite-based
# measures, producing the estimation samples behind Table 5.
#
# Input   PATHS$dataset                    (06_consolidate_dataset.R)
#         PATHS$acs_gini, PATHS$acs_theil  (01_compute_acs_inequality.R)
#         PATH_UCDB                        for urban centre representative points
# Output  <DIR_CLEAN>/case_studies/acs_matched_dmsp.parquet
#         <DIR_CLEAN>/case_studies/acs_matched_viirs.parquet
#
# WHY THE STATE IS INDISPENSABLE. IPUMS identifies cities by name and state; the
# UCDB carries no state field. Matching on city name alone collapses homonyms
# across states — Columbus OH and Columbus GA, Columbia SC and Columbia MD,
# Springfield IL, MA and MO — and a many-to-many join on the collapsed key
# produces a cartesian product of false pairs. The state is therefore recovered
# spatially: each urban centre's representative point is joined to Census state
# polygons from tigris, and the merge runs on (city name, state, year).
#
# Coastal urban centres whose representative point falls just outside the state
# polygon (Monterey, Atlantic City) are assigned to the nearest state rather
# than dropped.
#
# TWO SAMPLES, NOT ONE. The DMSP and VIIRS samples are filtered separately and
# never through a shared `drop_na`. Dropping rows missing any measure would cut
# the DMSP panel down to the years VIIRS covers, turning Panel A of Table 5 into
# a second copy of Panel B.
# ==============================================================================

source(here::here("src", "R", "setup.R"))

library(dplyr)
library(tidyr)
library(sf)
library(arrow)
library(readxl)

OUT_DMSP  <- file.path(DIR_CLEAN, "case_studies", "acs_matched_dmsp.parquet")
OUT_VIIRS <- file.path(DIR_CLEAN, "case_studies", "acs_matched_viirs.parquet")

require_input(PATHS$dataset, "01_data_construction/06_consolidate_dataset.R")
require_input(PATHS$acs_gini, "04_case_study_acs/01_compute_acs_inequality.R")
require_input(PATHS$acs_theil, "04_case_study_acs/01_compute_acs_inequality.R")
require_input(PATH_UCDB)


# ------------------------------------------------------------------------------
# 1. State of each US urban centre
# ------------------------------------------------------------------------------

log_step("Assigning US states to urban centres.")

ucdb_points <- st_read(
  PATH_UCDB, quiet = TRUE,
  query = "SELECT ID_HDC_G0, GCPNT_LAT, GCPNT_LON
           FROM GHS_STAT_UCDB2015MT_GLOBE_R2019A_V1_2
           WHERE CTR_MN_ISO = 'USA'"
) |>
  as.data.frame() |>
  st_as_sf(coords = c("GCPNT_LON", "GCPNT_LAT"), crs = 4326)

options(tigris_use_cache = TRUE)
us_states <- tigris::states(cb = TRUE, progress_bar = FALSE) |>
  select(state_abb = STUSPS) |>
  st_transform(4326)

state_lookup <- st_join(ucdb_points, us_states)

outside <- is.na(state_lookup$state_abb)
if (any(outside)) {
  log_step(sprintf("%d urban centre point(s) fell outside every state polygon; ",
                   sum(outside)), "assigning the nearest state.")
  nearest <- st_nearest_feature(state_lookup[outside, ], us_states)
  state_lookup$state_abb[outside] <- us_states$state_abb[nearest]
}

state_lookup <- state_lookup |>
  st_drop_geometry() |>
  select(city_id = ID_HDC_G0, state_abb)

stopifnot(!any(is.na(state_lookup$state_abb)))
log_step(sprintf("Assigned states to %s US urban centres.",
                 format(nrow(state_lookup), big.mark = ",")))


# ------------------------------------------------------------------------------
# 2. Census measures
# ------------------------------------------------------------------------------
# IPUMS writes CITY_NAME as "Boston, MA", so the state travels with the name.
# Split it out rather than discarding the suffix, which is what makes the
# homonyms distinguishable.

split_city_state <- function(df) {
  df |>
    filter(CITY_NAME != "Not in identifiable city (or size group)") |>
    mutate(
      city_name = trimws(gsub(",.*", "", CITY_NAME)),
      state_abb = trimws(sub("^[^,]*,", "", CITY_NAME))
    )
}

acs_gini <- read_excel(PATHS$acs_gini) |>
  split_city_state() |>
  select(city_name, state_abb, state_code = STATEFIP, year, gini)

acs_theil <- read_excel(PATHS$acs_theil) |>
  split_city_state() |>
  select(city_name, state_abb, year, theil)

acs <- inner_join(acs_gini, acs_theil, by = c("city_name", "state_abb", "year"))

# One census record per city-year, or the join below would fan out.
stopifnot(nrow(count(acs, city_name, state_abb, year) |> filter(n > 1)) == 0)
log_step(sprintf("Census measures: %s city-year records.",
                 format(nrow(acs), big.mark = ",")))


# ------------------------------------------------------------------------------
# 3. Satellite measures for US cities
# ------------------------------------------------------------------------------

dataset <- read_parquet(PATHS$dataset)

ntl_dmsp <- dataset |>
  select(country_name, iso_code, city_id, city_name, year,
         nl_gini_coef_dmsp, nl_theil_coef_dmsp) |>
  filter(iso_code == "USA") |>
  drop_na(nl_gini_coef_dmsp, nl_theil_coef_dmsp) |>
  left_join(state_lookup, by = "city_id")

ntl_viirs <- dataset |>
  select(country_name, iso_code, city_id, city_name, year,
         nl_gini_coef_viirs, nl_theil_coef_viirs) |>
  filter(iso_code == "USA", year %in% VIIRS_YEARS) |>
  drop_na(nl_gini_coef_viirs, nl_theil_coef_viirs) |>
  left_join(state_lookup, by = "city_id")

stopifnot(!any(is.na(ntl_dmsp$state_abb)), !any(is.na(ntl_viirs$state_abb)))


# ------------------------------------------------------------------------------
# 4. Merge on city, state and year
# ------------------------------------------------------------------------------
# An inner join: city-years without an exact match on all three keys are
# excluded rather than approximated.

matched_dmsp <- inner_join(ntl_dmsp, acs, by = c("city_name", "state_abb", "year")) |>
  rename(gini_nl_dmsp = nl_gini_coef_dmsp, theil_nl_dmsp = nl_theil_coef_dmsp,
         gini_acs = gini, theil_acs = theil)

matched_viirs <- inner_join(ntl_viirs, acs, by = c("city_name", "state_abb", "year")) |>
  rename(gini_nl_viirs = nl_gini_coef_viirs, theil_nl_viirs = nl_theil_coef_viirs,
         gini_acs = gini, theil_acs = theil)

# Permanent guard against the homonym fan-out described in the header.
stopifnot(
  nrow(count(matched_dmsp,  city_name, state_abb, year) |> filter(n > 1)) == 0,
  nrow(count(matched_viirs, city_name, state_abb, year) |> filter(n > 1)) == 0
)

log_step(sprintf("Matched samples: DMSP %s obs | VIIRS %s obs.",
                 format(nrow(matched_dmsp), big.mark = ","),
                 format(nrow(matched_viirs), big.mark = ",")))
log_step(sprintf("DMSP years: %s | VIIRS years: %s",
                 paste(sort(unique(matched_dmsp$year)), collapse = ", "),
                 paste(sort(unique(matched_viirs$year)), collapse = ", ")))


# ------------------------------------------------------------------------------
# 5. Write
# ------------------------------------------------------------------------------

write_parquet(matched_dmsp,  prepare_output(OUT_DMSP))
write_parquet(matched_viirs, prepare_output(OUT_VIIRS))
log_step("Wrote ", OUT_DMSP)
log_step("Wrote ", OUT_VIIRS)
