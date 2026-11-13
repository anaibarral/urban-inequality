# ==============================================================================
# centroids.R
#
# Population-weighted centroids of the urban centres and great-circle distances
# from grid cells to them. Used by step 4b of the dataset construction.
# ==============================================================================

#' Population-weighted centroid of every city-year.
#'
#' @param cells  Cell-level table with city_id, year, x, y (cell centre, degrees)
#'               and a population column.
#' @param pop    Name of the population column used as weights.
#' @param polys  sf polygons of the urban centres with column ID_HDC_G0.
#' @return       data.table city_id, year, lon, lat, moved (1 if the centroid fell
#'               outside the polygon and was moved to its nearest point).
#'
#' The centroid is the population-weighted mean of the cell coordinates, over
#' cells with positive population. For crescent-shaped or fragmented polygons it
#' can fall outside the urban centre; those centroids are moved to the nearest
#' point of the polygon so that the centre lies in the city.
population_weighted_centroids <- function(cells, pop, polys) {
  dt <- data.table::as.data.table(cells)[, .(city_id, year, x, y, w = .SD[[1]]), .SDcols = pop]
  pwc <- dt[w > 0, .(lon = stats::weighted.mean(x, w), lat = stats::weighted.mean(y, w)), by = .(city_id, year)]

  old_s2 <- sf::sf_use_s2(FALSE)
  on.exit(sf::sf_use_s2(old_s2), add = TRUE)
  pts <- sf::st_as_sf(pwc, coords = c("lon", "lat"), crs = 4326)
  hits <- sf::st_intersects(pts, polys)
  pwc[, moved := as.integer(!mapply(function(h, id) id %in% polys$ID_HDC_G0[h], hits, city_id))]

  k <- which(pwc$moved == 1L)
  if (length(k)) {
    poly <- polys[match(pwc$city_id[k], polys$ID_HDC_G0), ]
    snapped <- do.call(rbind, lapply(seq_along(k), function(i) {
      line <- suppressMessages(sf::st_nearest_points(pts[k[i], ], sf::st_cast(poly[i, ], "MULTILINESTRING")))
      sf::st_coordinates(line)[2, c("X", "Y")]
    }))
    pwc[k, `:=`(lon = snapped[, 1], lat = snapped[, 2])]
  }
  pwc[]
}

#' Great-circle distance in metres on a sphere of radius 6,371.01 km, the model
#' that sf/s2 uses for the distances of step 2.
great_circle_distance <- function(lon1, lat1, lon2, lat2, r = 6371010) {
  to <- pi / 180
  a <- sin((lat2 - lat1) * to / 2)^2 + cos(lat1 * to) * cos(lat2 * to) * sin((lon2 - lon1) * to / 2)^2
  2 * r * asin(pmin(1, sqrt(a)))
}
