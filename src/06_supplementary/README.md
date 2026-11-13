# Supplementary Information

Reproduces every table and figure of the Supplementary Information document.

```bash
Rscript src/00_run_all.R supplementary
```

| Script | Section | Needs |
|---|---|---|
| `table_si_ghspop.R` | S1. Results with GHS-POP population | main dataset (`*_ghs` columns), capital panel and ACS matched samples |
| `table_si_pwc_gradients.R` | S2. Population-weighted centroids | main dataset (`nl_gradient_pwc_*`, step 4b) and the capital panel |
| `table_si_epoch_validation.R` | S3. Time-varying urban boundaries | epoch dataset, bundled ACS aggregates |
| `table_si_tract_validation.R` | S4. Census tract validation for US urban centers | main dataset, bundled tract aggregates |
| `table_si_census_validation.R` | S5. Census validation for Mexico and Brazil | epoch dataset, bundled census aggregates |
| `table_si_dmsp_topcoding.R` | S6. DMSP top-coding | main dataset and its cell files (step 3) |
| `01_mexico_census_inequality.R` | builds `data/census_mexico/` | INEGI microdata (not bundled) |
| `02_brazil_census_inequality.R` | builds `data/census_brazil/` | IBGE microdata and municipal boundaries (not bundled) |
| `03_us_tract_inequality.R` | builds `data/census_us_tracts/` | Census tract boundaries and ACS 5-year tables (downloaded, needs `CENSUS_API_KEY`), cell files (step 3) |
| `latex.R` | helpers that write the tables as LaTeX | — |

Files are named by content (`table_si_<section>_<table>`), not by their number
in the document, so the order of the tables can change without renaming them.

Steps 01 to 03 build the census inputs. Their outputs are aggregate statistics
and ship with the repository (see `data/README.md`), so the `supplementary`
stage does not run them. Step 03 downloads census tract boundaries (`tigris`)
and ACS 5-year tables from the Census Data API, which needs a free key in the
environment variable `CENSUS_API_KEY`
(https://api.census.gov/data/key_signup.html). This product uses the Census
Bureau Data API but is not endorsed or certified by the Census Bureau.

Outputs: CSVs in `outputs/tables/`, LaTeX fragments in
`outputs/tables/supplementary/`, figures in `outputs/figures/supplementary/`.

## Contents

**Section S1. Results with GHS-POP population.** Tables 3 to 5 of the paper
with the indicators computed with GHS-POP R2023A population (dataset columns
`*_ghs`) instead of GPW, on the same 2015 polygons, cells and lights. The ACS
matched samples of Table 5 are reused, since the match on city name, state and
year does not depend on the population source.

**Section S2. Population-weighted centroids.** Tables 3 and 4 of the paper
with luminosity gradients measured from the population-weighted centroid of each
city and year (GPW population) instead of the city centroid of the main dataset
(a point inside the 2015 polygon from `st_point_on_surface()`).
The gradients are columns of the main dataset (`nl_gradient_pwc_*`), built in
step 4b of the data construction (`src/01_data_construction/04b_estimate_gradients_pwc.R`).

**Section S3. Time-varying urban boundaries.** Tables 3 to 5 of the paper
recomputed on the epoch dataset (`src/05_epoch_dataset/`), where each urban center
is measured inside its GHS-UCDB R2024A polygon of each epoch. DMSP lights, GPW
population. Capital status is the R2024A indicator (`GC_UCM_CAP`).

**Section S4. Census tract validation for US urban centers.** Income
inequality between census tracts inside the polygon of each US urban center of
the main dataset, in 2010, 2015 and 2020 (ACS 5-year tables B01003 and B19025,
2006-2010, 2011-2015 and 2016-2020). Each tract is assigned to the urban center
that contains its interior point (`st_point_on_surface`). One table with two
panels, Gini and Theil under DMSP and VIIRS, without fixed effects and with
state and year fixed effects:

- Panel A: the nightlights indices of the dataset (between 1 km cells);
- Panel B: the nightlights indices between the same tracts.

**Section S5. Census validation for Mexico and Brazil.** Table 5 of the paper
with census data, on the epoch dataset (DMSP, GPW):

- Mexico, 2010, 2015 and 2020. Household income from work (`INGTRHOG`) in the
  INEGI census samples, for households in localities of 50,000 or more (the only
  localities identified in the microdata). Each locality is placed at its ITER
  2020 coordinates and assigned to the urban center whose polygon of the census
  year contains it. Several localities in one urban center are pooled.
- Brazil, 2000 and 2010. Total household income in the IBGE census samples, by
  municipality. Each urban center takes the municipality that covers the largest
  share of its polygon of the census year.

**Section S6. DMSP top-coding.** In 2015 and 2020, the VIIRS − DMSP difference in
the Gini and the Theil is related to the share of top-coded DMSP cells (DN = 63),
on the main dataset:

- a binned scatter (cities without top-coded cells at zero and ten equal-size
  groups of the cities with top-coded cells) with two linear fits, over all
  city-years and over the sample of the third column of the table;
- one regression table with controls (log number of cells, share of cells at
  zero), year and country fixed effects, in three samples: all cities, cities
  with top-coded cells, and cities with top-coded cells without the 0.5% most
  top-coded city-years of each year (63 per year, 126 in total). Only the
  coefficient on the share of top-coded cells is shown.
