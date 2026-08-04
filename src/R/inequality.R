# ==============================================================================
# inequality.R
#
# The three estimators of the Urban Inequality Dataset, defined once and shared
# by the DMSP and VIIRS branches of the pipeline.
#
# Keeping them here rather than repeating them per source guarantees that the
# two NTL sources are processed with identical code, which is what makes the
# cross-source comparison in the paper meaningful.
#
# Notation follows the Methods section of the paper:
#   NL_g      nighttime light intensity in grid cell g
#   POP_g     population density in grid cell g (persons per sq. km)
#   NLpc_g    per-capita luminosity, NL_g / POP_g
#   d_gc      geodesic distance from the centre of cell g to the city centroid
# ==============================================================================


# ------------------------------------------------------------------------------
# Dispersion indices
# ------------------------------------------------------------------------------

#' Population-weighted Gini coefficient of per-capita luminosity.
#'
#' @param x Numeric vector of per-capita luminosity, one element per grid cell.
#' @param w Numeric vector of population weights (cell population density).
#' @return  A scalar in [0, 1].
#'
#' Computed with `DescTools::Gini(unbiased = FALSE)`, the plug-in estimator that
#' matches the formula in the paper. The index is invariant to the scale of the
#' weights, so passing raw population density is equivalent to passing
#' normalised population shares.
#'
#' Cells with zero population must already have been removed by the caller: the
#' per-capita ratio is undefined for them. Cells with zero luminosity but
#' positive population are kept and contribute according to their weight.
gini_weighted <- function(x, w) {
  DescTools::Gini(x = x, weights = w, unbiased = FALSE, na.rm = TRUE)
}


#' Population-weighted Theil T index of per-capita luminosity.
#'
#' @param x Numeric vector of per-capita luminosity, strictly positive.
#' @param w Numeric vector of population weights (cell population density).
#' @return  A non-negative scalar, unbounded above.
#'
#' Implements the definition used in the paper directly:
#'
#'     Theil = sum_g w_g * (x_g / mu) * log(x_g / mu),
#'     w_g   = POP_g / sum(POP_g),
#'     mu    = sum_g w_g * x_g          (the population-weighted mean)
#'
#' Written out rather than taken from a package. `REAT::theil` (v3.0.3) is not
#' usable here for three reasons: it returns NA when any observation is
#' non-positive, discarding the whole city-year rather than the offending cell;
#' it combines an unweighted mean with weighted deviations, which can produce
#' negative values; and it divides by n a second time, deflating the index by
#' the number of cells so that it partly measures city size.
#'
#' In near-perfectly equal cities floating point returns values of order -1e-16.
#' Those are numerical zeros and are truncated; a negative value larger than the
#' tolerance indicates a real problem and is left for the caller to catch.
theil_weighted <- function(x, w) {
  ok <- is.finite(x) & is.finite(w) & x > 0 & w > 0
  x <- x[ok]
  w <- w[ok]
  if (length(x) < 2L) return(NA_real_)

  ws <- w / sum(w)
  mu <- sum(ws * x)
  r  <- x / mu
  max(sum(ws * r * log(r)), 0)
}


#' Compute a dispersion index for every city-year in a cell-level table.
#'
#' @param cells   Cell-level data with columns city_id, year, nl_measure,
#'                pop_density.
#' @param index   Either "gini" or "theil".
#' @param cl      An optional registered parallel cluster.
#' @return        One row per city-year with the index and the cell count used.
#'
#' The two indices differ only in which cells are admissible, and that
#' difference is the reason the Theil is available for fewer city-years than the
#' Gini in the published dataset:
#'
#'   Gini   POP_g > 0 and NLpc_g finite
#'   Theil  the above, and additionally NL_g > 0, since the log is undefined
#'          at zero. The Theil therefore describes inequality among lit,
#'          populated cells, while the Gini also counts unlit populated ones.
compute_dispersion_index <- function(cells, index = c("gini", "theil")) {
  index <- match.arg(index)

  admissible <- cells |>
    dplyr::mutate(nl_per_capita = nl_measure / pop_density) |>
    dplyr::filter(pop_density > 0, is.finite(nl_per_capita))

  if (index == "theil") {
    admissible <- dplyr::filter(admissible, nl_per_capita > 0)
  }

  estimator <- if (index == "gini") gini_weighted else theil_weighted
  value_col <- if (index == "gini") "nl_gini_coef" else "nl_theil_coef"

  admissible |>
    dplyr::group_by(city_id, year) |>
    dplyr::filter(dplyr::n() >= MIN_CELLS_DISPERSION) |>
    dplyr::summarise(
      value    = estimator(nl_per_capita, pop_density),
      n_cells_used = dplyr::n(),
      .groups  = "drop"
    ) |>
    dplyr::filter(is.finite(value)) |>
    dplyr::rename(!!value_col := value) |>
    dplyr::arrange(city_id, year)
}


# ------------------------------------------------------------------------------
# Centre-periphery gradients
# ------------------------------------------------------------------------------

#' Fit one city-year luminosity gradient by OLS.
#'
#' @param df               Cells of a single city-year, with nl_measure,
#'                         dist_mt and pop_density.
#' @param population_control Include asinh(POP_g) as a regressor?
#' @return                 A one-row data frame, or NULL if the fit fails.
#'
#' The specification is
#'
#'     asinh(NL_g) = alpha + beta * asinh(d_gc) [ + gamma * asinh(POP_g) ] + e_g
#'
#' All continuous variables enter in inverse hyperbolic sine form. asinh
#' behaves like log(2x) for large x but stays defined at zero, which matters
#' for distance: cells whose centres sit almost on the city centroid have
#' d_gc near zero.
#'
#' beta is the reported gradient. Negative values mean luminosity falls from
#' the centre towards the periphery. With the population control, beta is net
#' of demographic thinning at the urban fringe, so it separates cities whose
#' periphery is simply emptier from cities whose periphery is genuinely darker
#' per resident.
fit_city_gradient <- function(df, population_control) {
  formula <- if (population_control) {
    asinh(nl_measure) ~ asinh(dist_mt) + asinh(pop_density)
  } else {
    asinh(nl_measure) ~ asinh(dist_mt)
  }

  reg <- tryCatch(fixest::feols(formula, data = df), error = function(e) NULL)
  if (is.null(reg)) return(NULL)

  coefs  <- stats::coef(reg)
  errs   <- fixest::se(reg)
  pvals  <- fixest::pvalue(reg)
  tstats <- fixest::tstat(reg)

  slope <- "asinh(dist_mt)"
  res <- data.frame(
    city_id   = unique(df$city_id),
    year      = unique(df$year),
    beta_1    = coefs[slope],
    se_1      = errs[slope],
    p_value1  = pvals[slope],
    t_stat1   = tstats[slope],
    beta_0    = coefs["(Intercept)"],
    se_0      = errs["(Intercept)"],
    p_value0  = pvals["(Intercept)"],
    t_stat0   = tstats["(Intercept)"],
    type_reg  = if (population_control) "Pop control reg" else "No pop control reg",
    n_obs     = fixest::nobs(reg),
    row.names = NULL
  )

  # 95% intervals, used by the gradient distribution figure (Figure 2).
  res$ci_high1 <- res$beta_1 + 1.96 * res$se_1
  res$ci_low1  <- res$beta_1 - 1.96 * res$se_1
  res$ci_high0 <- res$beta_0 + 1.96 * res$se_0
  res$ci_low0  <- res$beta_0 - 1.96 * res$se_0

  res
}


#' Estimate gradients for every city-year in a cell-level table.
#'
#' @param cells              Cell-level data joined to grid-centroid distances.
#' @param population_control Passed through to `fit_city_gradient()`.
#' @return                   One row per estimable city-year.
#'
#' Cells with zero luminosity or zero population are dropped before estimation,
#' and city-years left with fewer than `MIN_CELLS_GRADIENT` cells are skipped
#' for lack of degrees of freedom. Both filters are applied for both
#' specifications, so the two gradient columns share a missingness pattern and
#' remain directly comparable.
compute_gradients <- function(cells, population_control) {
  tasks <- cells |>
    tidyr::drop_na(dist_mt) |>
    dplyr::filter(nl_measure > 0, pop_density > 0) |>
    dplyr::group_by(city_id, year) |>
    dplyr::filter(dplyr::n() >= MIN_CELLS_GRADIENT) |>
    dplyr::ungroup() |>
    dplyr::group_split(city_id, year)

  log_step(sprintf("Fitting %s gradients for %s city-years.",
                   if (population_control) "population-controlled" else "unconditional",
                   format(length(tasks), big.mark = ",")))

  results <- foreach::foreach(
    k = seq_along(tasks),
    .packages = c("fixest", "dplyr"),
    .combine = "rbind",
    .errorhandling = "remove",
    .export = c("fit_city_gradient")
  ) %dopar% {
    fit_city_gradient(tasks[[k]], population_control)
  }

  if (is.null(results) || nrow(results) == 0) {
    stop("No gradients were estimated. Check the cell-level input.", call. = FALSE)
  }

  dplyr::arrange(results, city_id, year)
}
