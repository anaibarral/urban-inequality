# Epoch dataset

Builds a second dataset on the urban centre polygons of the GHS Urban Centre
Database R2024A, multitemporal edition (MTUC). There, each urban centre has a
different polygon in every epoch, so a city's metrics in a year are measured
inside the boundary it had in that year. The main dataset, in contrast, keeps
the 2015 polygons of R2019A fixed over the whole period.

| Step | Script | Produces |
|---|---|---|
| 1 | `01_population_centroids.R` | Population-weighted centroid of every polygon, by epoch (GHS-POP) |
| 2 | `02_grid_distances.R` | The 1 km cells of every polygon and their distance to the centroid |
| 3 | `03_extract_ntl_and_population.R` | DMSP and VIIRS lights, GPW and GHS-POP population, per cell |
| 4 | `04_compute_metrics.R` | Gradients, Gini and Theil: two NTL sources × two population sources |
| 5 | `05_consolidate_dataset.R` | The epoch dataset, its codebook, and the crosswalk to the main dataset |
| — | `table_e_validation_epoch.R` | Tables 3 to 6 of the paper, computed on the epoch dataset |

Run it with:

```bash
Rscript src/00_run_all.R epoch
```

## How it differs from the main dataset

| | Main dataset | Epoch dataset |
|---|---|---|
| Polygons | GHS-UCDB R2019A, 2015 boundary, fixed | GHS-UCDB R2024A MTUC, boundary of each epoch |
| Grid | 30 arc-second DMSP pixels | 1 km GHS-POP pixels (Mollweide), on which the polygons are drawn |
| City centre | Point on the polygon's surface | Population-weighted centroid (GHS-POP) of the epoch's polygon |
| Population | GPW counts | GPW counts (`_gpw`) and GHS-POP counts (`_ghs`) |
| Capital status | Name match against a reference list | The database's own indicator (`GC_UCM_CAP`) |
| Rows | City-years with at least one metric | Urban centre-epochs with grid cells |

The estimators are the same (`src/R/inequality.R`). Lights and GPW population
are projected onto the 1 km cells: lights as the mean of the pixels in each
cell, GPW as the area-weighted sum, which preserves the population total.

Country, region and name come from the 2025 attribute layer of the MTUC
database. About 6% of the urban centres with a polygon in some epoch are absent
from it (by 2025 they merged into another urban centre or fell below the
thresholds), and a few have no country there; they take the country and region
of the nearest urban centre of that layer, and their name is left missing.

## The crosswalk

The two databases use different identifiers. `crosswalk_ucdb2015_epoch_ucdb2024`
matches each urban centre of the main dataset, in each epoch, to the MTUC
polygon with the largest area of intersection. It reports the share of the 2015
polygon covered and flags MTUC polygons matched by more than one 2015 urban
centre (for instance, cities that merged). It is a convenience for linking the
two datasets, not a substitute for either: a matched pair does not describe the
same area unless the overlap is close to one.

## Runtime

Steps 1 to 3 take about half an hour each on 6 cores (one epoch per core);
step 4 fits about 330,000 regressions.
