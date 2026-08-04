# ==============================================================================
# plotting.R
#
# Shared figure styling and output helpers, so every exhibit in the paper is
# produced with the same theme, palette and dimensions.
# ==============================================================================

library(ggplot2)

# Palette used across the figures.
PAL <- list(
  point     = "#1c4966",  # gradient point estimates
  interval  = "#3792cb",  # confidence intervals and scatter points
  reference = "red",      # zero reference line
  capital   = "tomato",   # capital cities
  other     = "steelblue" # non-capital cities
)


#' Minimal theme shared by all figures in the paper.
theme_urban <- function(base_size = 11) {
  theme_minimal(base_size = base_size) +
    theme(
      plot.title      = element_text(hjust = 0.5, face = "plain"),
      panel.grid.minor = element_blank(),
      plot.margin     = margin(10, 10, 10, 10)
    )
}


#' Save a figure to `outputs/figures/` at the dimensions used in the paper.
#'
#' @param plot     A ggplot object.
#' @param filename File name, including extension.
#' @param width,height Inches.
save_figure <- function(plot, filename, width = 10, height = 6, dpi = 300) {
  path <- path_figure(filename)
  ggsave(filename = path, plot = plot, width = width, height = height, dpi = dpi)
  log_step("Figure written: ", path)
  invisible(path)
}


#' Write a table to `outputs/tables/` as CSV, and echo it to the console.
#'
#' Exhibits are saved as CSV rather than as formatted LaTeX so that the numbers
#' can be diffed between runs. The manuscript formatting lives in the .tex file.
save_table <- function(df, filename) {
  path <- path_table(filename)
  readr::write_csv(df, path)
  log_step("Table written: ", path)
  print(as.data.frame(df), row.names = FALSE)
  invisible(path)
}
