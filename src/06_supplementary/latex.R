# ==============================================================================
# latex.R
#
# Small helpers that write the supplementary tables as LaTeX fragments
# (booktabs), in the format of the tables of the paper. Sourced by the table_s*
# scripts of this folder. Fragments go to outputs/tables/supplementary/.
# ==============================================================================

SI_TABLE_DIR <- file.path(DIR_OUTPUT, "tables", "supplementary")
SI_FIGURE_DIR <- file.path(DIR_OUTPUT, "figures", "supplementary")
dir.create(SI_TABLE_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(SI_FIGURE_DIR, recursive = TRUE, showWarnings = FALSE)

stars_tex <- function(p) {
  ifelse(is.na(p), "", ifelse(p < 0.01, "$^{***}$", ifelse(p < 0.05, "$^{**}$", ifelse(p < 0.10, "$^{*}$", ""))))
}
num <- function(x, d = 3) ifelse(is.na(x), "", formatC(x, format = "f", digits = d))
int <- function(x) formatC(x, format = "d", big.mark = ",")
coef_tex <- function(est, p, d = 3) paste0(sub("^-", "$-$", num(est, d)), stars_tex(p))
se_tex <- function(se, d = 3) paste0("(", num(se, d), ")")

#' A complete table environment: caption, tabular body and a note.
#' `body` is a character vector of tabular lines (without the \begin{tabular}).
#' `fit = TRUE` scales the tabular down to the text width when it is wider
#' (needs the adjustbox package in the document preamble).
write_si_table <- function(file, caption, colspec, body, note, label = NULL, size = NULL, fit = FALSE) {
  lines <- c(
    "\\begin{table}[H]",
    "\\centering",
    paste0("\\caption{", caption, "}"),
    if (!is.null(label)) paste0("\\label{", label, "}"),
    "\\singlespacing",
    if (!is.null(size)) size,
    if (fit) "\\begin{adjustbox}{max width=\\textwidth}",
    paste0("\\begin{tabular}{", colspec, "}"),
    body,
    "\\end{tabular}",
    if (fit) "\\end{adjustbox}",
    "\\begin{flushleft}",
    paste0("\\footnotesize\\textit{Note:} ", note),
    "\\end{flushleft}",
    "\\end{table}"
  )
  writeLines(lines, file.path(SI_TABLE_DIR, file), useBytes = TRUE)
  log_step("Wrote ", file.path(SI_TABLE_DIR, file))
}

STARS_NOTE <- "$^{***}$ p $<$ 0.01; $^{**}$ p $<$ 0.05; $^{*}$ p $<$ 0.1."
