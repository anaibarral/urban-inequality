# Data construction

Builds the Urban Inequality Dataset from raw rasters and polygons. Six steps,
run in order.

| Step | Script | Produces |
|---|---|---|
| 1 | `01_build_urban_centre_grids.R` | One square polygon per ~1 km grid cell inside each urban centre, plus its centroid |
| 2 | `02_compute_grid_distances.R` | Geodesic distance from every cell centroid to its city centroid |
| 3 | `03_extract_ntl_and_population.R` | Cell-level luminosity and population, for both NTL sources |
| 4 | `04_estimate_gradients.R` | Four gradient columns: two specifications × two sources |
| 5 | `05_compute_dispersion_indices.R` | Gini and Theil, for both sources |
| 6 | `06_consolidate_dataset.R` | The published 70,024 × 17 panel |

Run the whole sequence with:

```bash
Rscript src/00_run_all.R dataset
```

## Why the two NTL sources share a script

Steps 3, 4 and 5 each process DMSP and VIIRS inside a single script rather than
in a `_dmsp` / `_viirs` pair of files. The estimators live in
`src/R/inequality.R` and are called by both branches.

This is deliberate. Every metric in the paper is reported for both sources and
compared directly — Table 6 Panel C is entirely about their agreement — and that
comparison only means something if the two were built from the same cells, the
same population input and the same code. Two sibling scripts drift: one gets a
fix, one reads a differently organised folder, one is run from a different
machine. Nothing downstream raises an error when they do; the metrics simply
stop being comparable.

Two guards enforce this rather than trusting it:

- `resolve_rasters_by_year()` in `src/R/setup.R` requires exactly one raster per
  benchmark year and searches recursively, so a reorganised folder fails loudly
  instead of silently changing the input set.
- Step 3 ends by checking that the DMSP and VIIRS extractions cover identical
  cells, at identical coordinates, carrying identical population values. It
  stops with a diagnostic if they do not.

## Estimability thresholds

A city-year enters the dataset when at least one metric could be computed. The
metrics have a hierarchy of requirements, which is why their coverage differs:

| Metric | Requires | Coverage (DMSP) |
|---|---|---|
| Gini | ≥ 2 populated cells, non-zero total luminosity | 99.9% |
| Theil | ≥ 2 populated **and lit** cells (the log needs positive values) | 99.5% |
| Gradients | ≥ 5 populated and lit cells (degrees of freedom) | 93.8% |

Step 5 asserts the implication of this hierarchy — every city-year with a Theil
must have a Gini — rather than leaving it to be discovered during validation.

## Runtime

Hours, not minutes. Step 1 builds roughly 920,000 grid polygons, step 3 extracts
eight global raster pairs, step 4 fits about 175,000 city-year regressions. Each
step writes to disk, so a failed run resumes by invoking the remaining scripts
directly.

Parallelism comes from `N_CORES` in `config.R`.
