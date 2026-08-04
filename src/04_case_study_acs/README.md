# Case study 2 — ACS external validation

Do satellite-based inequality measures track survey-based income inequality?
Benchmarks the NTL Gini and Theil against American Community Survey household
microdata for US cities, where high-quality income data exist. Produces
**Table 5**.

| Step | Script | Produces |
|---|---|---|
| 1 | `01_compute_acs_inequality.R` | Census Gini and Theil per city-year, from IPUMS microdata |
| 2 | `02_match_acs_to_urban_centres.R` | The two matched estimation samples |
| 3 | `table_05_acs_validation.R` | Table 5, the log-log appendix table, and scatterplots |

```bash
Rscript src/04_case_study_acs/01_compute_acs_inequality.R
Rscript src/04_case_study_acs/02_match_acs_to_urban_centres.R
Rscript src/04_case_study_acs/table_05_acs_validation.R
```

## Getting the IPUMS data

The extracts are not redistributable and must be requested from
[IPUMS USA](https://usa.ipums.org/usa/). Build one extract per ACS sample
(2000, 2005, 2010, 2015, 2020) with at least `YEAR`, `SERIAL`, `HHWT`,
`HHINCOME`, `CITY` and `STATEFIP`. Place each `.xml` DDI file and its `.dat.gz`
in `DIR_ACS_IPUMS`; step 1 discovers them automatically.

## The state is what makes the merge valid

IPUMS identifies cities by name **and state**. The UCDB has no state field.
Matching on city name alone collapses homonyms — Columbus OH and Columbus GA,
Columbia SC and Columbia MD, Springfield IL, MA and MO — and a many-to-many join
on the collapsed key produces a cartesian product of false pairs that inflates N
and corrupts the coefficients.

Step 2 recovers the state spatially: each urban centre's representative point is
joined to Census state polygons from `tigris`, with coastal points that fall
just outside a polygon assigned to the nearest state rather than dropped. The
merge then runs on city name, state and year, and the script asserts afterwards
that no city-year appears twice.

## Sample sizes and why the two panels are built separately

The DMSP and VIIRS samples are filtered independently and never through a shared
`drop_na`. Requiring every measure to be present would cut the DMSP panel down
to the years VIIRS covers, making Panel A a second copy of Panel B.

| Panel | Source | Years | N |
|---|---|---|---|
| A | DMSP | 2000–2020 | 420 |
| B | VIIRS | 2015, 2020 | 116 |

The VIIRS sample is small because it is the intersection of two restrictions:
VIIRS exists only for 2015 and 2020, and the set of cities IPUMS identifies
individually shrank in the recent ACS waves. Table 5's least precise cell — the
Theil under VIIRS with the full set of fixed effects — is where those two bind
at once.

## Comparability of the two sides

The census measures apply the same exclusions as their luminosity counterparts:
the IPUMS missing code and negative incomes are dropped from both, and zero
incomes are additionally dropped from the Theil, mirroring the exclusion of
zero-luminosity cells.

One difference remains. The ACS Gini is computed with
`DescTools::Gini(unbiased = TRUE)` while the luminosity Gini uses
`unbiased = FALSE`. The published results were produced this way and the setting
is preserved so the repository reproduces the paper. The two differ by a factor
of n/(n-1), which on samples of thousands of households is a fourth-decimal
effect — well below the precision Table 5 reports. It is still an inconsistency
with the paper's statement that the same functional forms are used on both
sides, and it is flagged in the script rather than quietly reconciled.

## Levels, not logs

Table 5 reports the levels regressions. Both specifications are estimated; the
log-log results answer a different question — an elasticity rather than a slope
— and are written separately as `table_a01_acs_validation_logs.csv`.
