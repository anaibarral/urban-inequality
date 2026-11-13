# ==============================================================================
# 05_consolidate_dataset.R
#
# Epoch dataset, step 5 of 5. Assembles the epoch dataset, its codebook, and a
# crosswalk to the urban centres of the main dataset.
#
# Input   PATHS$epoch_metrics   (step 4)
#         PATHS$epoch_cells     (step 3)
#         PATHS$epoch_centroids (step 1)
#         PATH_UCDB_MTUC, PATH_UCDB_2024, PATH_UCDB
# Output  PATHS$epoch_dataset, PATHS$epoch_codebook
#         PATHS$crosswalk,     PATHS$crosswalk_codebook
#
# ONE ROW PER URBAN CENTRE AND EPOCH. Each row is an urban centre of the R2024A
# multitemporal database in a benchmark year, measured inside its polygon of
# that year. Every urban centre-epoch with grid cells is included; metrics that
# cannot be estimated are left missing. Metrics carry the population source in
# their name: _gpw (GPW counts) or _ghs (GHS-POP counts).
#
# THE CROSSWALK. The two databases use different identifiers. For each urban
# centre of the main dataset (R2019A, 2015 polygons) and each epoch, the
# crosswalk gives the MTUC polygon of that epoch with the largest area of
# intersection (in Mollweide), the share of the 2015 polygon it covers, and a
# flag when two 2015 urban centres are matched to the same MTUC polygon.
# ==============================================================================

source(here::here("src", "R", "setup.R"))
source(here::here("src", "R", "sources.R"))

library(dplyr)
library(tidyr)
library(sf)
library(arrow)
library(readr)

require_input(PATHS$epoch_metrics, "05_epoch_dataset/04_compute_metrics.R")
require_input(PATHS$epoch_cells, "05_epoch_dataset/03_extract_ntl_and_population.R")
require_input(PATHS$epoch_centroids, "05_epoch_dataset/01_population_centroids.R")
require_input(PATH_UCDB_MTUC)
require_input(PATH_UCDB_2024)


# ------------------------------------------------------------------------------
# 1. Attributes of the MTUC urban centres
# ------------------------------------------------------------------------------
# Some names in the R2024A files are UTF-8 encoded twice ("MÃ©xico" for
# "México"); fix_double_utf8() reverts that only where it applies.

fix_double_utf8 <- function(s) {
  r <- iconv(s, from = "UTF-8", to = "latin1")
  ok <- !is.na(r) & validUTF8(r) & grepl("[ÃÂ]", s)
  s[ok] <- r[ok]
  Encoding(s) <- "UTF-8"
  s
}

mtuc_points <- st_read(PATH_UCDB_MTUC, layer = "GHSL_UCDB_MTUC_GLOBE_R2024", quiet = TRUE)
mtuc <- st_drop_geometry(mtuc_points)
general <- st_read(PATH_UCDB_2024, layer = "GHSL_UCDB_THEME_GENERAL_CHARACTERISTICS_GLOBE_R2024A", quiet = TRUE) |>
  st_drop_geometry()

# Country codes are matched on the ASCII form of the name: countrycode's
# patterns do not recognise accented spellings such as "México".
iso3 <- function(country) {
  countrycode::countrycode(stringi::stri_trans_general(country, "Latin-ASCII"), "country.name", "iso3c",
                           warn = FALSE, custom_match = c("Kosovo" = "XKX"))
}

# Every urban centre-epoch of the dataset, with the location of its most recent
# polygon (population-weighted centroid, step 1).
centroids <- read_parquet(PATHS$epoch_centroids) |>
  dplyr::arrange(city_id, dplyr::desc(year)) |>
  dplyr::distinct(city_id, .keep_all = TRUE)

attributes <- tibble::tibble(city_id = centroids$city_id) |>
  dplyr::mutate(
    k            = match(city_id, mtuc$ID_MTUC_G0),
    city_name    = mtuc$GC_UCN_MAI_2025[k],
    country_name = fix_double_utf8(mtuc$GC_CNT_GAD_2025[k]),
    region       = mtuc$GC_DEV_USR_2025[k]
  )

# About 6% of the urban centres that have a polygon in some epoch are absent
# from the 2025 attribute layer (by 2025 they merged into another urban centre
# or fell below the urban centre thresholds), and a few others have no country
# there. They take the country and region of the nearest urban centre of the
# attribute layer that has one (distances in Mollweide). Their name is left
# missing.
no_country <- is.na(attributes$country_name)
if (any(no_country)) {
  ref <- mtuc_points[!is.na(mtuc_points$GC_CNT_GAD_2025), c("GC_CNT_GAD_2025", "GC_DEV_USR_2025")]
  ref <- st_transform(ref, "ESRI:54009")
  pts <- st_as_sf(centroids[no_country, ], coords = c("lon_pwc", "lat_pwc"), crs = 4326) |>
    st_transform("ESRI:54009")
  nearest <- st_nearest_feature(pts, ref)
  attributes$country_name[no_country] <- fix_double_utf8(ref$GC_CNT_GAD_2025[nearest])
  attributes$region[no_country] <- ifelse(is.na(attributes$region[no_country]),
                                          ref$GC_DEV_USR_2025[nearest], attributes$region[no_country])
  log_step(sprintf("Country assigned from the nearest urban centre for %s urban centres.",
                   format(sum(no_country), big.mark = ",")))
}

attributes <- attributes |>
  dplyr::select(-k) |>
  dplyr::mutate(
    iso_code = iso3(country_name),
    # National capital: indicator of the full R2024A database (same
    # identifiers). Urban centres absent from it are coded 0.
    is_capital = as.integer(general$GC_UCM_CAP[match(city_id, general$ID_UC_G0)]),
    is_capital = dplyr::coalesce(is_capital, 0L)
  )
stopifnot(!anyNA(attributes$country_name))
unmatched_iso <- unique(attributes$country_name[is.na(attributes$iso_code)])
if (length(unmatched_iso)) log_step("No ISO code for: ", paste(unmatched_iso, collapse = ", "))


# ------------------------------------------------------------------------------
# 2. Totals per urban centre-epoch and dataset
# ------------------------------------------------------------------------------

totals <- read_parquet(PATHS$epoch_cells) |>
  dplyr::group_by(city_id, year) |>
  dplyr::summarise(
    nl_sum_dmsp   = sum(nl_dmsp, na.rm = TRUE),
    nl_sum_viirs  = if (dplyr::first(year) %in% VIIRS_YEARS) sum(nl_viirs, na.rm = TRUE) else NA_real_,
    total_pop_gpw = sum(pop_gpw, na.rm = TRUE),
    total_pop_ghs = sum(pop_ghs, na.rm = TRUE),
    n_cells       = dplyr::n_distinct(grid_cell_id),
    .groups = "drop"
  )

METRICS <- c("nl_gradient_no_pop_dmsp", "nl_gradient_no_pop_viirs", "nl_gradient_pop_dmsp", "nl_gradient_pop_viirs",
             "nl_gini_coef_dmsp", "nl_gini_coef_viirs", "nl_theil_coef_dmsp", "nl_theil_coef_viirs")
METRIC_COLS <- c(paste0(METRICS, "_gpw"), paste0(METRICS, "_ghs"))

epoch <- totals |>
  dplyr::left_join(read_parquet(PATHS$epoch_metrics), by = c("city_id", "year")) |>
  dplyr::left_join(attributes, by = "city_id") |>
  dplyr::rename(city_id_epoch_ucdb2024 = city_id) |>
  dplyr::select(country_name, iso_code, region, city_id_epoch_ucdb2024, city_name, year, is_capital,
                dplyr::all_of(METRIC_COLS),
                nl_sum_dmsp, nl_sum_viirs, total_pop_gpw, total_pop_ghs, n_cells) |>
  dplyr::arrange(city_id_epoch_ucdb2024, year)

stopifnot(!anyDuplicated(epoch[c("city_id_epoch_ucdb2024", "year")]))

log_step(sprintf("Epoch dataset: %s rows, %s urban centres.",
                 format(nrow(epoch), big.mark = ","), format(dplyr::n_distinct(epoch$city_id_epoch_ucdb2024), big.mark = ",")))
print(table(epoch$year))


# ------------------------------------------------------------------------------
# 3. Codebook
# ------------------------------------------------------------------------------

describe_metric <- function(v) {
  measure <- dplyr::case_when(
    grepl("gradient_no_pop", v) ~ "Luminosity gradient without population control (slope of asinh(lights) on asinh(distance to the population-weighted centroid))",
    grepl("gradient_pop", v)    ~ "Luminosity gradient with population control (slope of asinh(lights) on asinh(distance to the population-weighted centroid), controlling for asinh(population))",
    grepl("gini", v)            ~ "Population-weighted Gini coefficient of per-capita luminosity across grid cells",
    grepl("theil", v)           ~ "Population-weighted Theil index of per-capita luminosity across grid cells"
  )
  source <- ifelse(grepl("_dmsp", v), "DMSP lights (all years)", "VIIRS VNL v2.1 lights (2015, 2020)")
  population <- ifelse(grepl("_ghs$", v), "GHS-POP R2023A population counts", "GPW population counts")
  paste0(measure, "; ", source, "; ", population, "; GHS-UCDB R2024A MTUC polygon of the epoch (1 km GHS grid)")
}

descriptions <- c(
  country_name  = "Country name (GHS-UCDB R2024A)",
  iso_code      = "ISO 3166-1 alpha-3 country code",
  region        = "World region (GHS-UCDB R2024A)",
  city_id_epoch_ucdb2024 = "Urban centre identifier (GHS-UCDB R2024A multitemporal urban centres, ID_MTUC_G0); the polygon changes with the epoch",
  city_name     = "Urban centre main name (GHS-UCDB R2024A)",
  year          = "Benchmark year (epoch): 1995, 2000, 2005, 2010, 2015, 2020",
  is_capital    = "1 if the urban centre contains the national capital (GHS-UCDB R2024A, GC_UCM_CAP)",
  nl_sum_dmsp   = "Total DMSP lights (DN) over the epoch polygon's 1 km grid cells",
  nl_sum_viirs  = "Total VIIRS VNL v2.1 radiance (nW/cm2/sr) over the epoch polygon's 1 km grid cells (2015, 2020)",
  total_pop_gpw = "Total population: sum of GPW population counts over the epoch polygon's grid cells (GPWv4 Rev. 11 for 2000-2020; GPWv3 UN-adjusted for 1995)",
  total_pop_ghs = "Total population: sum of GHS-POP R2023A population counts over the epoch polygon's grid cells",
  n_cells       = "Number of 1 km GHS grid cells (Mollweide) with any part inside the epoch polygon"
)

codebook <- tibble::tibble(variable = names(epoch)) |>
  dplyr::mutate(
    description = dplyr::coalesce(unname(descriptions[variable]), describe_metric(variable)),
    type        = vapply(epoch[variable], function(z) class(z)[1], character(1)),
    non_missing = vapply(epoch[variable], function(z) sum(!is.na(z)), integer(1))
  ) |>
  add_source_columns(source_ids_epoch)   # inputs and licences (src/R/sources.R)


# ------------------------------------------------------------------------------
# 4. Crosswalk to the 2015 polygons of the main dataset
# ------------------------------------------------------------------------------

require_input(PATH_UCDB)
log_step("Building the crosswalk between the R2019A and R2024A polygons.")

sf_use_s2(FALSE)
p15 <- st_read(PATH_UCDB, quiet = TRUE)[, "ID_HDC_G0"]
p15 <- st_make_valid(st_transform(p15, "ESRI:54009"))
names(p15)[1] <- "city_id"
p15$area15 <- as.numeric(st_area(p15))

crosswalk <- dplyr::bind_rows(lapply(BENCHMARK_YEARS, function(yr) {
  pm <- st_make_valid(st_read(PATH_UCDB_MTUC, layer = paste0("GHSL_UCDB_MTUC_", yr, "_GLOBE_R2024"), quiet = TRUE)[, "ID_UC_G0"])
  ii <- st_intersection(p15[, c("city_id", "area15")], pm)
  tibble::tibble(city_id = ii$city_id, id24 = ii$ID_UC_G0, area15 = ii$area15, inter = as.numeric(st_area(ii))) |>
    dplyr::arrange(city_id, dplyr::desc(inter)) |>
    dplyr::distinct(city_id, .keep_all = TRUE) |>
    dplyr::transmute(city_id, year = yr, city_id_epoch_ucdb2024 = id24,
                     epoch_ucdb2024_overlap = round(inter / area15, 4))
})) |>
  dplyr::group_by(year, city_id_epoch_ucdb2024) |>
  dplyr::mutate(epoch_ucdb2024_shared = as.integer(dplyr::n() > 1)) |>
  dplyr::ungroup() |>
  dplyr::arrange(city_id, year)

crosswalk_codebook <- tibble::tibble(
  variable = names(crosswalk),
  description = c(
    "Urban centre identifier (GHS-UCDB R2019A, ID_HDC_G0; key of the main dataset)",
    "Benchmark year (epoch)",
    "GHS-UCDB R2024A MTUC urban centre of that epoch with the largest area of intersection with the 2015 polygon (key of the epoch dataset)",
    "Share of the 2015 polygon area covered by that R2024A polygon (Mollweide)",
    "1 if another 2015 urban centre is matched to the same R2024A polygon in that epoch"
  )
)

log_step(sprintf("Crosswalk: %s urban centre-epochs of the main dataset matched.", format(nrow(crosswalk), big.mark = ",")))


# ------------------------------------------------------------------------------
# 5. Write
# ------------------------------------------------------------------------------

write_parquet(epoch, prepare_output(PATHS$epoch_dataset))
readr::write_excel_csv(epoch, sub("\\.parquet$", ".csv", PATHS$epoch_dataset))
readr::write_csv(codebook, prepare_output(PATHS$epoch_codebook))
write_sources_table()
write_parquet(crosswalk, prepare_output(PATHS$crosswalk))
readr::write_excel_csv(crosswalk, sub("\\.parquet$", ".csv", PATHS$crosswalk))
readr::write_csv(crosswalk_codebook, prepare_output(PATHS$crosswalk_codebook))

log_step("Wrote ", PATHS$epoch_dataset, ", ", PATHS$crosswalk, " and their codebooks.")
