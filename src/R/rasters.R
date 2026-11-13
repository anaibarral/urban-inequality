# ==============================================================================
# rasters.R
#
# Raster helpers shared by the extraction steps of the main dataset
# (01_data_construction/03) and of the epoch dataset (05_epoch_dataset/03).
# ==============================================================================

gauss_1d <- function(sigma_px) {
  h <- max(1, ceiling(3 * sigma_px))
  k <- exp(-(-h:h)^2 / (2 * sigma_px^2))
  k / sum(k)
}

smooth_crop <- function(r, e_ll, sigma_km) {
  lat    <- mean(c(e_ll$ymin, e_ll$ymax))
  km_lon <- 111.32 * cos(lat * pi / 180)
  km_lat <- 111.32
  rc <- terra::crop(r, terra::extend(e_ll, max(0.02, 3.2 * sigma_km / km_lon)), snap = "out")
  if (sigma_km == 0) return(rc)
  rc <- terra::classify(rc, cbind(NA, 0))
  rc <- terra::focal(rc, w = matrix(gauss_1d(sigma_km / (km_lon * terra::res(rc)[1])), nrow = 1),
                     fun = "sum", na.rm = TRUE, fillvalue = 0)
  terra::focal(rc, w = matrix(gauss_1d(sigma_km / (km_lat * terra::res(rc)[2])), ncol = 1),
               fun = "sum", na.rm = TRUE, fillvalue = 0)
}


#' Area-weighted mean of a raster over square grid cells.
#'
#' @param r     A raster (lon/lat).
#' @param x, y  Centres of the cells, in the raster's coordinates.
#' @param half  Half the side of each cell, in the same units.
#' @return      One value per cell: the mean of the raster pixels that overlap
#'              the cell, weighted by the overlapping area. NA where no pixel
#'              with data overlaps the cell.
#'
#' Used to carry a raster whose pixels are finer than, or not aligned with, the
#' analysis grid onto the cells of that grid.
area_mean_at_cells <- function(r, x, y, half) {
  rx <- terra::res(r)[1]
  ry <- terra::res(r)[2]
  e  <- terra::ext(r)
  num <- 0
  den <- 0
  c0 <- terra::colFromX(r, x)
  r0 <- terra::rowFromY(r, y)
  k  <- ceiling(2 * half / min(rx, ry)) + 1
  for (dc in -k:k) for (dr in -k:k) {
    cc <- c0 + dc
    rr <- r0 + dr
    px_lo <- e$xmin + (cc - 1) * rx
    px_hi <- px_lo + rx
    py_hi <- e$ymax - (rr - 1) * ry
    py_lo <- py_hi - ry
    ox <- pmax(0, pmin(x + half, px_hi) - pmax(x - half, px_lo))
    oy <- pmax(0, pmin(y + half, py_hi) - pmax(y - half, py_lo))
    w  <- ox * oy
    v  <- rep(NA_real_, length(x))
    ok <- !is.na(cc) & !is.na(rr) & cc >= 1 & cc <= ncol(r) & rr >= 1 & rr <= nrow(r) & w > 0
    if (any(ok)) v[ok] <- r[terra::cellFromRowCol(r, rr[ok], cc[ok])][, 1]
    use <- !is.na(v) & w > 0
    num <- num + ifelse(use, w * v, 0)
    den <- den + ifelse(use, w, 0)
  }
  ifelse(den > 0, num / den, NA_real_)
}


#' Population count raster carried to points by bilinear interpolation.
#'
#' @param r       Population count raster (persons per pixel).
#' @param xy      Two-column matrix of points (cell centres).
#' @param cell_res Resolution of the analysis grid, in the raster's units.
#' @return        Persons per analysis cell.
#'
#' A count belongs to the pixel's area, so when the source pixels are coarser
#' than the analysis cells (GPWv3 in 1995: 2.5 arc-minutes against 30
#' arc-seconds) the interpolated value is rescaled by the ratio of cell areas.
#' For a source on the analysis resolution the ratio is one.
population_at_points <- function(r, xy, cell_res) {
  v <- terra::extract(r, xy, method = "bilinear")[, 1]
  ratio <- (cell_res[1] * cell_res[2]) / prod(terra::res(r))
  if (abs(ratio - 1) > 1e-6) v <- v * ratio
  v
}

#' Pixels of each polygon, with their value and index in the global raster.
#'
#' @param r     Single-layer raster.
#' @param polys sf polygons in the raster's CRS.
#' @return      data.frame with ID (row of polys), cell (global index), x, y
#'              and value. A pixel belongs to a polygon when its centre falls
#'              inside it.
#'
#' The raster is cropped to each polygon before extracting, which avoids
#' reading the global raster once per polygon.
values_in_polygons <- function(r, polys) {
  v <- terra::vect(polys)
  out <- lapply(seq_len(nrow(v)), function(i) {
    rc <- tryCatch(terra::crop(r, v[i], snap = "out"), error = function(e) NULL)
    if (is.null(rc)) return(NULL)
    e <- terra::extract(rc, v[i], xy = TRUE, ID = FALSE)
    if (!nrow(e)) return(NULL)
    data.frame(ID = i, cell = terra::cellFromXY(r, cbind(e$x, e$y)), x = e$x, y = e$y, value = e[[1]])
  })
  do.call(rbind, out)
}
