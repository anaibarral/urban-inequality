# The Urban Inequality Dataset

Code to build the Urban Inequality Dataset and to reproduce every exhibit in
*The Urban Inequality Dataset: A remote-sensing approach to economic disparities
within cities around the globe*.

The dataset is a harmonized panel of intra-urban economic disparity measures for
**12,315 cities across 182 countries**, over six benchmark years between **1995
and 2020** with 70,024 city-year observations. It combines satellite nighttime
lights with gridded population estimates inside functionally defined urban
boundaries, and reports three complementary measures per city-year: a Gini
coefficient, a Theil index, and centre-periphery luminosity gradients estimated
with and without population controls.

| | |
|---|---|
| **Data** | [Harvard Dataverse, doi:10.7910/DVN/ECLI7X](https://doi.org/10.7910/DVN/ECLI7X) (CC0) |
| **Format** | Apache Parquet, 70,024 × 17, with a data dictionary and summary statistics alongside |
| **Files** | `urban_inequality_dataset_1995_2020.parquet`, `ui_codebook.xlsx`, `ui_summary_stats.xlsx` |

---

## Quick start

```bash
git clone https://github.com/anaibarral/urban-inequality.git
cd urban-inequality
cp config.example.R config.R      # then edit the paths in config.R
```

```bash
Rscript src/00_run_all.R              # build the dataset, then all exhibits
Rscript src/00_run_all.R dataset      # dataset only
Rscript src/00_run_all.R exhibits     # exhibits only, from an existing dataset
```

If you only want the exhibits, download the dataset from the Dataverse and point
`PATHS$dataset` at it; the raw rasters are not needed.

---

## Repository layout

```
├── config.example.R              copy to config.R and set your paths
├── data/
│   ├── reference/                capitals list (versioned)
│   └── acs/                      census inequality aggregates (versioned)
├── src/
│   ├── 00_run_all.R              master script
│   ├── R/
│   │   ├── setup.R               config loader, path helpers, constants
│   │   ├── inequality.R          the three estimators, shared by both sources
│   │   └── plotting.R            figure theme and output helpers
│   ├── 01_data_construction/     six steps, raw rasters to published panel
│   ├── 02_validation/            Table 2, Figure 2, Table 3, Table 6
│   ├── 03_case_study_capitals/   Table 4
│   └── 04_case_study_acs/        Table 5
└── outputs/
    ├── tables/                   generated, git-ignored
    └── figures/                  generated, git-ignored
```

Each `src/` subfolder has its own README covering the decisions specific to it.

---

## Reproducing the exhibits

Listed in the order they appear in the paper.

| Exhibit | Script | Notes |
|---|---|---|
| Figure 1 — Construction pipeline | — | Not code-generated. An infographic designed in Canva |
| Table 1 — Variable descriptions | — | Not computed. See the data dictionary in the Dataverse deposit |
| Table 2 — Data quality summary | `src/02_validation/table_02_data_quality.R` | Also prints every figure quoted in Technical Validation |
| Figure 2 — Gradient distributions by year | `src/02_validation/figure_02_gradient_distributions.R` | |
| Table 3 — % negative gradients | `src/02_validation/table_03_negative_gradients.R` | |
| Table 4 — Capital vs non-capital | `src/03_case_study_capitals/table_04_capital_gradients.R` | Requires `01_build_capital_panel.R` first |
| Table 5 — Satellite vs census (ACS) | `src/04_case_study_acs/table_05_acs_validation.R` | Requires steps 1 and 2 of that folder |
| Table 6 — Pairwise correlations | `src/02_validation/table_06_pairwise_correlations.R` | |

Tables are written as CSV rather than formatted LaTeX, so that values can be
diffed between runs; the manuscript formatting lives in the `.tex` file.

### Verified against the published dataset

Every computed exhibit above has been run against the deposited dataset and
reproduces the manuscript:

- **Table 2** — all values, including 70,024 / 12,315 / 182, 94.8% panel
  completeness, and every completeness percentage.
- **Table 3** — 86.3 / 85.2 / 86.4 / 85.3 / 84.0 / 84.4 (DMSP) and 84.3 / 85.1
  (VIIRS), with sample sizes from 10,642 to 11,245.
- **Table 4** — every coefficient, standard error and sample size, both panels.
- **Table 5** — every coefficient, standard error and R², both panels.
- **Table 6** — all three panels, N = 65,704 and 22,256.

---

## Building the dataset

Six steps, described in
[`src/01_data_construction/README.md`](src/01_data_construction/README.md).

1. **Grids** — each urban centre polygon becomes a set of ~1 km grid cells.
2. **Distances** — geodesic distance from each cell centroid to the city centroid.
3. **Extraction** — luminosity and population per cell, both NTL sources.
4. **Gradients** — one OLS regression per city-year, two specifications.
5. **Dispersion indices** — population-weighted Gini and Theil.
6. **Consolidation** — the published panel, with integrity checks.

Expect hours, not minutes: roughly 920,000 grid polygons, eight global raster
pairs, and about 175,000 city-year regressions. Every step writes to disk, so a
failed run resumes by invoking the remaining scripts directly.

### Methods in one paragraph each

**Gradients.** `asinh(NL_g) = α + β·asinh(d_gc) [+ γ·asinh(POP_g)] + ε_g`, fitted
separately per city-year. The inverse hyperbolic sine behaves like `log(2x)` for
large `x` but stays defined at zero, which matters for distance: cells sitting
almost on the centroid have `d_gc ≈ 0`. β is the reported gradient; negative
means luminosity falls towards the periphery. With the population control, β is
net of demographic thinning, separating cities whose fringe is merely emptier
from cities whose fringe is genuinely darker per resident.

**Gini.** Population-weighted Gini of per-capita luminosity `NL_g / POP_g`
across the cells of a city. Weighting by population makes the index reflect
inequality as experienced by residents rather than across equal-area units.
Cells with zero population are dropped (the ratio is undefined); cells that are
unlit but populated stay in and push the index up.

**Theil.** Population-weighted Theil T, written out from its definition rather
than taken from a package. `REAT::theil` (v3.0.3) is unusable here: it returns
`NA` when any observation is non-positive, discarding the whole city-year rather
than the offending cell; it mixes an unweighted mean with weighted deviations,
which can produce negative values; and it divides by *n* a second time,
deflating the index by city size. Because the index takes logarithms, zero-light
cells are excluded, so the Theil describes inequality among lit, populated cells
while the Gini also counts unlit ones — which is why the Theil covers fewer
city-years.

---

## Data sources

None of the inputs are redistributed here. All are public except the IPUMS
extracts, which require a free account.

| Input | Source | Used for |
|---|---|---|
| GHS Urban Centre Database R2019A | [European Commission JRC](https://human-settlement.emergency.copernicus.eu/ghs_stat_ucdb2015mt_r2019a.php) | City boundaries and identifiers |
| Extended DMSP-like NTL, 1992–2020 | [EOG, Colorado School of Mines](https://eogdata.mines.edu/products/dmsp/) | Luminosity, all six years |
| VIIRS VNL v2.1 annual composites | [EOG, Colorado School of Mines](https://eogdata.mines.edu/products/vnl/) | Luminosity, 2015 and 2020 |
| GPWv4 Population Density, Rev. 11 | [NASA SEDAC](https://doi.org/10.7927/H49C6VHW) | Population, 2000–2020 |
| GPWv3 Population Density Grid | [NASA SEDAC](https://doi.org/10.7927/H4XK8CG2) | Population, 1995 |
| ACS microdata | [IPUMS USA](https://usa.ipums.org/usa/) | Case study 2, step 1 only |

Expected folder layout under `DIR_RAW`:

```
raw/
├── ghsl/GHS_STAT_UCDB2015MT_GLOBE_R2019A_V1_2.gpkg
├── ntl/dmsp_annual/*.tif          one composite per benchmark year
├── ntl/viirs_annual/*.tif         one composite for 2015 and 2020
├── population/*.tif               one density raster per benchmark year
└── acs_usa_ipums/*.xml + *.dat.gz   optional, see below
```

### Bundled with the repository

Two small, redistributable inputs ship in `data/`, so a fresh clone runs both
case studies without any download:

| File | Used by |
|---|---|
| `data/reference/country-capitals.csv` | Case study 1, in full |
| `data/acs/acs_gini_by_city.xlsx`, `acs_theil_by_city.xlsx` | Case study 2, steps 2–3 |

The ACS files are city-level **aggregates** (one row per city-year) computed
from IPUMS microdata by step 1 of the case study. Publishing aggregates derived
from IPUMS is permitted; redistributing the extracts is not, and at 2.1 GB they
would exceed GitHub's file-size limit anyway. So the extracts are not here, and
step 1 is the only script that needs them.
[`data/README.md`](data/README.md) documents the samples and variables to
request if you want to rebuild them.

**One population raster per year, and only one.** `resolve_rasters_by_year()`
searches `DIR_POPULATION` recursively and requires exactly one match per
benchmark year. If two variants of the same year are present (say the
UN-WPP-adjusted and unadjusted versions) the pipeline stops rather than picking
one arbitrarily. This is what keeps the DMSP and VIIRS branches on the same
population input; see
[`src/01_data_construction/README.md`](src/01_data_construction/README.md).

---

## Requirements

R ≥ 4.1 (the scripts use the native `|>` pipe).

```r
install.packages(c(
  # infrastructure
  "here", "arrow", "readr", "readxl", "writexl",
  # data
  "dplyr", "tidyr", "purrr", "tibble", "stringi", "rlang",
  # spatial
  "sf", "terra", "tigris",
  # estimation
  "fixest", "DescTools", "broom",
  # parallel
  "foreach", "doParallel",
  # figures
  "ggplot2", "patchwork",
  # case study 2
  "ipumsr"
))
```

---

## Citation

```bibtex
@article{moralesarilla_ibarra_urban_inequality,
  author  = {Morales-Arilla, Jos{\'e} and Ibarra, Ana},
  title   = {The Urban Inequality Dataset: A remote-sensing approach to
             economic disparities within cities around the globe},
  year    = {2026}
}

@data{ibarra_morales_2026_dataverse,
  author    = {Ibarra Luces, Ana Gabriela and Morales-Arilla, Jose},
  title     = {The Urban Inequality Dataset: A Remote Sensing Approach to
               Global Urban Disparities},
  year      = {2026},
  publisher = {Harvard Dataverse},
  doi       = {10.7910/DVN/ECLI7X}
}
```

## License

Code in this repository is released under the MIT License. The dataset itself is
released under CC0 through the Harvard Dataverse. Input datasets remain under
the licences of their respective providers.

## Contact

José Morales-Arilla — josemoralesarilla@tec.mx
Ana Ibarra — aibarral@ucab.edu.ve
