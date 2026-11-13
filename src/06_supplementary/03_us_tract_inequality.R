# ==============================================================================
# 03_us_tract_inequality.R
#
# Supplementary Information, Section S4, step 1. Income and nightlights
# inequality between census tracts, for the US urban centres of the main
# dataset (GHS-UCDB R2019A 2015 polygons).
#
#   1. Census tract polygons (TIGER/Line cartographic boundary files, through
#      tigris): 2010 tracts (2015 edition) and 2020 tracts (2020 edition).
#   2. Each tract is assigned to the urban centre whose polygon contains its
#      interior point (sf::st_point_on_surface, which always falls inside the
#      tract, also for irregular or concave tracts; then st_within). Each tract
#      belongs to one urban centre at most.
#   3. ACS 5-year detailed tables by tract, from the Census Data API:
#      B01003 total population and B19025 aggregate household income. The
#      periods 2006-2010, 2011-2015 and 2016-2020 are matched to 2010, 2015
#      and 2020. Income per capita = aggregate income / population.
#   4. Lights per tract: the 1 km cells of the dataset are intersected with the
#      tract polygons. Each cell contributes the share of its lights and GPW
#      population that falls in the tract. Lights per capita = lights / GPW
#      population, as in the dataset.
#   5. Per urban centre and year, the Gini and Theil of income per capita and of
#      lights per capita between its tracts, weighted by ACS tract population,
#      with the estimators of src/R/inequality.R. At least 5 tracts per city.
#
# Needs a Census Data API key in the environment variable CENSUS_API_KEY (free,
# https://api.census.gov/data/key_signup.html). Its output is an aggregate table
# that ships with the repository (data/census_us_tracts/), so the supplementary
# stage does not run this script.
#
# Input   PATH_UCDB, PATHS$grids, PATHS$cells_dmsp, PATHS$cells_viirs
# Output  PATHS$us_tract_inequality
# Cache   <DIR_CLEAN>/us_tracts/ (tract polygons and ACS tables, re-used on reruns)
#
# This product uses the Census Bureau Data API but is not endorsed or certified
# by the Census Bureau.
# ==============================================================================

source(here::here("src", "R", "setup.R"))
source(here::here("src", "R", "inequality.R"))

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(sf); library(jsonlite)
})
sf_use_s2(FALSE)
options(tigris_use_cache = TRUE)

KEY <- Sys.getenv("CENSUS_API_KEY")
if (!nzchar(KEY)) stop("Set CENSUS_API_KEY (Census Data API key) in the R environment.", call. = FALSE)

CACHE <- file.path(DIR_CLEAN, "us_tracts")
dir.create(CACHE, showWarnings = FALSE, recursive = TRUE)

ACS_YEARS  <- c(2010, 2015, 2020)
TRACT_VINT <- c(`2010` = 2015, `2015` = 2015, `2020` = 2020)   # 2010 tracts in the 2015 edition
MIN_TRACTS <- 5
AEA        <- 5070   # Albers equal area, used only for area shares


# ------------------------------------------------------------------------------
# 1. US urban centres and states
# ------------------------------------------------------------------------------

require_input(PATH_UCDB)
uc <- st_read(PATH_UCDB, quiet = TRUE,
              query = "SELECT * FROM GHS_STAT_UCDB2015MT_GLOBE_R2019A_V1_2 WHERE CTR_MN_ISO = 'USA'")
uc <- st_make_valid(st_transform(uc[, "ID_HDC_G0"], 4326))
names(uc)[1] <- "city_id"
log_step(sprintf("US urban centres: %d.", nrow(uc)))

states <- tigris::states(cb = TRUE, progress_bar = FALSE)
states <- st_transform(states[, c("STATEFP", "STUSPS")], 4326)
st_fips <- sort(unique(stats::na.omit(st_join(uc, states)$STATEFP)))

# State of each urban centre (for state fixed effects): the state that covers most of its area.
city_state <- st_intersection(uc, states)
city_state$a <- as.numeric(st_area(st_transform(city_state, AEA)))
city_state <- as.data.table(st_drop_geometry(city_state))[order(-a)][, .SD[1], by = city_id][, .(city_id, state_code = STUSPS)]


# ------------------------------------------------------------------------------
# 2. Tracts and their assignment to urban centres
# ------------------------------------------------------------------------------

get_tracts <- function(vint) {
  f <- file.path(CACHE, sprintf("tracts_%d.rds", vint))
  if (file.exists(f)) return(readRDS(f))
  tr <- do.call(rbind, lapply(st_fips, function(s) tigris::tracts(state = s, year = vint, cb = TRUE, progress_bar = FALSE)[, "GEOID"]))
  tr <- st_make_valid(st_transform(tr, 4326))
  saveRDS(tr, f)
  tr
}
assign_tracts <- function(tr) {
  pts <- suppressWarnings(st_point_on_surface(tr))
  j <- st_join(pts, uc, join = st_within)
  j <- j[!is.na(j$city_id), ]
  merge(tr, st_drop_geometry(j)[, c("GEOID", "city_id")], by = "GEOID")
}
tracts <- lapply(unique(TRACT_VINT), function(v) assign_tracts(get_tracts(v)))
names(tracts) <- unique(TRACT_VINT)
for (v in names(tracts)) log_step(sprintf("Tracts assigned (%s edition): %d in %d urban centres.",
                                          v, nrow(tracts[[v]]), length(unique(tracts[[v]]$city_id))))


# ------------------------------------------------------------------------------
# 3. ACS 5-year tables by tract
# ------------------------------------------------------------------------------

VARS <- c("B01003_001E", "B19025_001E")
acs_state <- function(y, s) {
  base <- sprintf("https://api.census.gov/data/%d/acs/acs5?get=%s&for=tract:*&in=state:%s", y, paste(VARS, collapse = ","), s)
  r <- tryCatch(fromJSON(paste0(base, "&key=", KEY)), error = function(e) NULL)
  if (is.null(r)) r <- fromJSON(paste0(base, "&in=county:*&key=", KEY))
  d <- as.data.table(r[-1, , drop = FALSE]); setnames(d, r[1, ])
  d[, GEOID := paste0(state, county, tract)]
  d[, (VARS) := lapply(.SD, as.numeric), .SDcols = VARS]
  d[, c("GEOID", VARS), with = FALSE]
}
acs <- rbindlist(lapply(ACS_YEARS, function(y) {
  f <- file.path(CACHE, sprintf("acs5_tracts_%d.rds", y))
  if (!file.exists(f)) saveRDS(rbindlist(lapply(st_fips, function(s) acs_state(y, s))), f)
  cbind(year = y, readRDS(f)[, c("GEOID", VARS), with = FALSE])
}))
setnames(acs, VARS, c("pop_acs", "agg_inc"))
for (v in c("pop_acs", "agg_inc")) acs[get(v) < 0, (v) := NA]   # the API codes missing values as large negatives


# ------------------------------------------------------------------------------
# 4. Lights per tract
# ------------------------------------------------------------------------------

cells_of <- function(path, yrs) {
  as.data.table(open_dataset(path) |>
    dplyr::filter(city_id %in% !!uc$city_id, year %in% !!yrs) |>
    dplyr::select(city_id, year, grid_cell_id, nl_measure, pop) |>
    dplyr::collect())
}
cells <- rbind(cbind(src = "dmsp",  cells_of(PATHS$cells_dmsp,  ACS_YEARS)),
               cbind(src = "viirs", cells_of(PATHS$cells_viirs, VIIRS_YEARS)))

grid <- st_read(PATHS$grids, quiet = TRUE,
                query = sprintf("SELECT * FROM city_grids WHERE city_id IN (%s)", paste(uc$city_id, collapse = ",")))
names(grid)[2] <- "grid_cell_id"
grid <- st_transform(grid, AEA)
grid$cell_area <- as.numeric(st_area(grid))

overlap <- lapply(names(tracts), function(v) {
  x <- st_intersection(grid, st_transform(tracts[[v]][, c("GEOID", "city_id")], AEA))
  x <- x[x$city_id == x$city_id.1, ]
  dt <- as.data.table(st_drop_geometry(x))[, .(city_id, grid_cell_id, GEOID)]
  dt[, share := as.numeric(st_area(x)) / x$cell_area]
  dt[share > 1e-6]
})
names(overlap) <- names(tracts)

nl_tract <- rbindlist(lapply(ACS_YEARS, function(y) {
  ov <- overlap[[as.character(TRACT_VINT[as.character(y)])]]
  m <- merge(cells[year == y], ov, by = c("city_id", "grid_cell_id"), allow.cartesian = TRUE)
  m[, .(nl = sum(nl_measure * share), pop_gpw = sum(pop * share)), by = .(src, city_id, year, GEOID)]
}))


# ------------------------------------------------------------------------------
# 5. Inequality between tracts, per urban centre and year
# ------------------------------------------------------------------------------

city_of <- rbindlist(lapply(ACS_YEARS, function(y) {
  tr <- tracts[[as.character(TRACT_VINT[as.character(y)])]]
  data.table(year = y, GEOID = tr$GEOID, city_id = tr$city_id)
}))
t_inc <- merge(acs, city_of, by = c("year", "GEOID"))[, inc_pc := agg_inc / pop_acs]

gini_w <- function(x, w) { ok <- is.finite(x) & is.finite(w) & w > 0; if (sum(ok) < 2) NA_real_ else gini_weighted(x[ok], w[ok]) }

inc_city <- t_inc[pop_acs > 0 & is.finite(inc_pc), .(
  gini_inc_tract = gini_w(inc_pc, pop_acs), theil_inc_tract = theil_weighted(inc_pc, pop_acs), n_tracts = .N),
  by = .(city_id, year)][n_tracts >= MIN_TRACTS]

t_nl <- merge(nl_tract, t_inc[, .(year, GEOID, pop_acs)], by = c("year", "GEOID"))
t_nl <- t_nl[pop_gpw > 0 & pop_acs > 0][, nl_pc := nl / pop_gpw]
nl_city <- dcast(t_nl[, .(gini_nl_tract = gini_w(nl_pc, pop_acs), theil_nl_tract = theil_weighted(nl_pc, pop_acs),
                          n = .N), by = .(src, city_id, year)][n >= MIN_TRACTS],
                 city_id + year ~ src, value.var = c("gini_nl_tract", "theil_nl_tract"))

out <- merge(inc_city, nl_city, by = c("city_id", "year"), all.x = TRUE)
out <- merge(out, city_state, by = "city_id", all.x = TRUE)
setcolorder(out, c("city_id", "year", "state_code", "n_tracts"))
setorder(out, city_id, year)
fwrite(out, prepare_output(PATHS$us_tract_inequality))
log_step(sprintf("Wrote %s: %d urban centre-years.", PATHS$us_tract_inequality, nrow(out)))
