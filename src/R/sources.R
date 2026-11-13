# ==============================================================================
# sources.R
#
# Input sources and licences, for the codebooks of the main and epoch datasets.
#
# The table of inputs lives in data/reference/data_sources_licenses.csv (one row
# per input: producer, files and years used, access URL or DOI, licence,
# required attribution, citation, primary source and the evidence that the
# primary source is open). Each codebook gets four extra columns that point to
# it:
#
#   source_ids      identifiers of the inputs used by the variable (S1, S2, ...)
#   input_datasets  short names of those inputs, with the years each one covers
#   license         licence of each input
#   source_url      access URL or DOI of each input
#
# The full table is written next to the codebooks as data_sources_licenses.csv.
# ==============================================================================

read_sources <- function(path = PATHS$sources) {
  require_input(path)
  readr::read_csv(path, show_col_types = FALSE, col_types = readr::cols(.default = "c"))
}

#' Inputs used by a variable of the main dataset (GHS-UCDB R2019A polygons).
source_ids_main <- function(v) {
  if (v == "year") return(character(0))
  if (v %in% c("country_name", "iso_code", "city_id", "city_name", "n_cells")) return("S7")
  if (v == "total_pop_gpw") return(c("S4", "S5", "S7"))
  if (v == "total_pop_ghs") return(c("S6", "S7"))
  if (v == "nl_sum_dmsp")   return(c("S1", "S2", "S7"))
  if (v == "nl_sum_viirs")  return(c("S3", "S7"))
  ntl <- if (grepl("_dmsp", v)) c("S1", "S2") else "S3"
  pop <- if (grepl("_ghs$", v)) "S6" else c("S4", "S5")
  c(ntl, pop, "S7")
}

#' Inputs used by a variable of the epoch dataset (GHS-UCDB R2024A polygons).
#' The gradients are measured from the population-weighted centroid of each
#' epoch polygon, which is computed with GHS-POP, so every gradient uses it.
source_ids_epoch <- function(v) {
  if (v == "year") return(character(0))
  if (v %in% c("country_name", "iso_code", "region", "city_id_epoch_ucdb2024",
               "city_name", "is_capital", "n_cells")) return("S8")
  if (v == "total_pop_gpw") return(c("S4", "S5", "S8"))
  if (v == "total_pop_ghs") return(c("S6", "S8"))
  if (v == "nl_sum_dmsp")   return(c("S1", "S2", "S8"))
  if (v == "nl_sum_viirs")  return(c("S3", "S8"))
  ntl <- if (grepl("_dmsp", v)) c("S1", "S2") else "S3"
  pop <- if (grepl("_ghs$", v)) "S6" else c("S4", "S5")
  if (grepl("gradient", v)) pop <- union(pop, "S6")
  c(ntl, pop, "S8")
}

#' Append the four source columns to a codebook with a `variable` column.
add_source_columns <- function(codebook, ids_fun, sources = read_sources()) {
  src <- split(sources, sources$source_id)
  pick <- function(ids, f) paste(vapply(ids, f, character(1)), collapse = "; ")
  label <- function(i) {
    s <- src[[i]]
    if (is.na(s$years_short) || s$years_short == "") s$short_name else paste0(s$short_name, " [", s$years_short, "]")
  }
  ids <- lapply(codebook$variable, ids_fun)
  unknown <- setdiff(unlist(ids), names(src))
  if (length(unknown) > 0) stop("Unknown source id(s): ", paste(unknown, collapse = ", "), call. = FALSE)
  codebook |>
    dplyr::mutate(
      source_ids     = vapply(ids, paste, character(1), collapse = ", "),
      input_datasets = vapply(ids, pick, character(1), f = label),
      license        = vapply(ids, pick, character(1), f = function(i) paste0(src[[i]]$short_name, ": ", src[[i]]$license_short)),
      source_url     = vapply(ids, function(x) paste(vapply(x, function(i) src[[i]]$access, character(1)), collapse = " | "), character(1))
    )
}

#' Write the full table of inputs next to the codebooks.
write_sources_table <- function(sources = read_sources(), path = PATHS$sources_out) {
  readr::write_csv(dplyr::select(sources, -short_name, -license_short, -years_short), prepare_output(path))
}
