# Technical validation

Exhibits that describe the dataset itself, as opposed to the two case studies.

| Exhibit | Script | Output |
|---|---|---|
| Table 2 | `table_02_data_quality.R` | `table_02_data_quality.csv`, plus attrition and per-metric completeness |
| Figure 2 | `figure_02_gradient_distributions.R` | `figure_02a_gradients_pop_dmsp.png`, `figure_02b_gradients_pop_viirs.png` |
| Table 3 | `table_03_negative_gradients.R` | `table_03_negative_gradients.csv` |
| Table 6 | `table_06_pairwise_correlations.R` | `table_06_pairwise_correlations.csv` |

All four read only the consolidated dataset, except Figure 2, which also reads
the gradient tables for confidence intervals.

## The denominator rule

VIIRS composites exist for 2015 and 2020 only. Every VIIRS quantity is therefore
summarised over those two years — 23,594 observations — and never over the full
70,024-row panel.

This is not cosmetic. Computed over the full panel, VIIRS Gini completeness
reads 33% rather than 99%, because 1995–2010 are counted as missing data instead
of as outside the sensor's coverage. The scripts express the rule through the
`VIIRS_YEARS` constant in `src/R/setup.R`, and `table_02_data_quality.R` asserts
that no VIIRS value exists outside those years.

The same trap appears in Table 6. Panel A selects the DMSP columns *before*
dropping missing values; dropping across all columns at once would require a
VIIRS value to be present, silently restricting the DMSP panel to 2015 and 2020
and turning Panel A into a second copy of Panel B on a different sample.

## Two things to know about Figure 2

**The caption in the current manuscript does not match the figure.** It
describes kernel density estimates. The panels are ranked coefficient plots:
cities sorted by their estimated gradient, each with a 95% confidence interval,
against a dashed line at zero. The share of the curve below zero is what Table 3
tabulates. Either the caption needs correcting or the figure needs replacing
with an actual density.

**Confidence intervals come from the matching specification.** The
population-controlled panels use intervals from the population-controlled
regressions, and the unconditional panels use their own. Pairing point estimates
from one specification with standard errors from the other draws bars that do
not belong to the plotted coefficients.
