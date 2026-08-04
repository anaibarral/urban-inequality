# Bundled data

Almost all inputs are downloaded rather than versioned: the rasters alone run to
tens of gigabytes and are reproducible from the sources listed in the main
README. Two things are small, redistributable and tedious to reconstruct, so
they ship with the repository.

```
data/
├── reference/country-capitals.csv     capital-city reference list
└── acs/
    ├── acs_gini_by_city.xlsx          census Gini,  by city-year
    └── acs_theil_by_city.xlsx         census Theil, by city-year
```

Both are wired into `config.example.R` as defaults, so a fresh clone runs the
capitals case study, and the ACS case study from step 2 onward, with no extra
downloads.

---

## `reference/country-capitals.csv`

14 KB · 245 rows · one row per country.

| Column | |
|---|---|
| `CountryName` | Country |
| `CapitalName` | Capital city |
| `CapitalLatitude`, `CapitalLongitude` | Coordinates, unused by the pipeline |
| `CountryCode` | ISO 3166-1 alpha-2 |
| `ContinentName` | Continent |

Used by `src/03_case_study_capitals/01_build_capital_panel.R`, which matches
`CountryName` and `CapitalName` against the UCDB after transliterating to ASCII
and lowercasing. Only those two columns are read.

Publicly circulated country/capital list, cited in the paper as
`techslides2013capitals`. Kept verbatim as downloaded, so the capital indicator
is reproducible exactly.

The known gaps in this match — 19 countries with no capital flagged, including
India, and two countries matching twice — are a property of joining this list to
UCDB names, not of the file itself. They are documented in
[`src/03_case_study_capitals/README.md`](../src/03_case_study_capitals/README.md).

---

## `acs/acs_gini_by_city.xlsx` and `acs/acs_theil_by_city.xlsx`

70 KB and 50 KB · 995 and 750 rows · one row per city-year.

Census-based inequality for US cities, computed from ACS household microdata by
`src/04_case_study_acs/01_compute_acs_inequality.R`. Samples: **2000, 2005,
2010, 2015, 2020**.

| Column | |
|---|---|
| `CITY_NAME` | IPUMS city label, `"City, ST"` |
| `STATEFIP` | State FIPS code (Gini file only) |
| `year` | ACS sample year |
| `gini` / `theil` | Inequality of household income, weighted by `HHWT` |
| `total_hogares_pond`, `total_obs` | Weighted and unweighted household counts |
| `na_*` | Records dropped: IPUMS missing code, negatives |

Rows labelled `"Not in identifiable city (or size group)"` are the residual
category and are filtered out at the matching step.

Identifiable cities per year: 181, 180, 180, 102, 102. The drop after 2010
reflects reduced geographic detail in recent ACS releases, and is why the VIIRS
panel of Table 5 has only 116 observations.

### Why these and not the microdata

These are **aggregate statistics**, not microdata: one row per city-year, no
household records. Publishing aggregate results derived from IPUMS is permitted;
redistributing the extracts is not.

---

## What is deliberately not here: the IPUMS extracts

The five ACS extracts behind those aggregates are **not** in this repository,
for two independent reasons — either one would be sufficient.

**Licence.** IPUMS USA terms of use prohibit redistributing extracts. Users must
request their own, which is free but requires an account and agreement to the
terms. This is the standard arrangement for IPUMS-based replication packages.

**Size.** The five extracts total about 2.1 GB uncompressed and 164 MB gzipped.
The largest single file is 1.08 GB, well past GitHub's 100 MB hard limit, and
committing them would permanently bloat the repository's history.

Shipping the derived aggregates is what makes this a non-issue in practice: only
step 1 of the ACS case study needs the microdata, and its output is already
here.

### Rebuilding the extracts

Should you need to re-run step 1, create one extract per sample at
[usa.ipums.org](https://usa.ipums.org/usa/) with these five samples:

> 2000 ACS · 2005 ACS · 2010 ACS · 2015 ACS · 2020 ACS

and these variables:

> `YEAR`, `SAMPLE`, `SERIAL`, `CBSERIAL`, `HHWT`, `CLUSTER`, `STATEICP`,
> `STATEFIP`, `CITY`, `CITYPOP`, `STRATA`, `GQ`, `HHINCOME`

`HHINCOME`, `HHWT`, `SERIAL`, `CITY`, `STATEFIP` and `YEAR` are the ones the
script reads; the rest come with the standard IPUMS preselection.

Place each `.xml` DDI file with its `.dat.gz` in the directory `DIR_ACS_IPUMS`
points at. Step 1 discovers them by scanning for `.xml`.
