# Bundled data

Almost all inputs are downloaded rather than versioned: the rasters alone run to
tens of gigabytes and are reproducible from the sources listed in the main
README. A few things are small, redistributable and tedious to reconstruct, so
they ship with the repository.

```
data/
├── supporting_data_README.txt       guide to the supporting data deposited in the Dataverse
├── reference/
│   ├── country-capitals.csv           capital-city reference list
│   └── data_sources_licenses.csv      inputs, licences and primary sources
├── acs/
│   ├── acs_gini_by_city.xlsx          census Gini,  by city-year
│   └── acs_theil_by_city.xlsx         census Theil, by city-year
├── census_mexico/
│   └── mexico_census_inequality_epoch_ucdb2024.csv   census Gini and Theil, by urban centre-epoch
├── census_brazil/
│   ├── brazil_census_inequality_by_municipality.csv  census Gini and Theil, by municipality-year
│   └── crosswalk_epoch_ucdb2024_municipality.csv     urban centre-epoch -> municipality
└── census_us_tracts/
    └── us_tract_inequality_city_year.csv             income and nightlights inequality between census tracts, by urban centre-year
```

The census files for Mexico, Brazil and US census tracts feed the
Supplementary Information (`src/06_supplementary/`).

`census_us_tracts/us_tract_inequality_city_year.csv` is built by
`src/06_supplementary/03_us_tract_inequality.R` from the ACS 5-year tables by
census tract and the Census Bureau tract boundaries (public domain). One row
per US urban centre and year (2010, 2015, 2020, 970 rows): `state_code`,
`n_tracts`, the Gini and Theil of per-capita income between tracts
(`gini_inc_tract`, `theil_inc_tract`) and of per-capita lights between the same
tracts (`gini_nl_tract_{dmsp,viirs}`, `theil_nl_tract_{dmsp,viirs}`). This
product uses the Census Bureau Data API but is not endorsed or certified by the
Census Bureau.

`supporting_data_README.txt` documents the eight `supporting_data_*.csv` files
deposited in the Harvard Dataverse (folder `supporting_data`): their columns,
sources, licences and the script that builds each one. Those files are the
deposit copies of the aggregates bundled here, plus the US state of each urban
centre and the variables of the DMSP top-coding test.

Both are wired into `config.example.R` as defaults, so a fresh clone runs the
capitals case study, and the ACS case study from step 2 onward, with no extra
downloads.

---

## `reference/data_sources_licenses.csv`

One row per input of the datasets and the validation (S1 to S13): producer,
files and years used, access URL or DOI, licence or terms of use, required
attribution, citation, primary source, the evidence that the primary source is
open, and what the repository or the deposit redistributes.

`src/R/sources.R` reads it to add four columns to the codebooks of the main and
epoch datasets: `source_ids`, `input_datasets` (with the years each input
covers), `license` and `source_url`. Steps 6 of the data construction and 5 of
the epoch dataset also write a copy of the table, without the short-name
columns, next to the codebooks (`data_sources_licenses.csv`).

| Source | Input | Licence |
|---|---|---|
| S1 | DMSP-OLS Nighttime Lights Version 4, 1995-2010 (EOG) | CC BY 4.0 |
| S2 | DMSP Nighttime Lights Extension series, 2015 and 2020 (EOG) | CC BY 4.0 |
| S3 | VIIRS VNL v2.1, 2015 and 2020 (EOG) | CC BY 4.0 |
| S4 | GPWv4 Population Count, Rev. 11, 2000-2020 (CIESIN) | CC BY 4.0 |
| S5 | GPWv3 Population Count Grid, 1995 (CIESIN, FAO, CIAT) | Derived products with acknowledgement of CIESIN and CIAT |
| S6 | GHS-POP R2023A (JRC) | CC BY 4.0 |
| S7 | GHS-UCDB R2019A (JRC), main dataset | CC BY 4.0 |
| S8 | GHS-UCDB R2024A (JRC), epoch dataset | CC BY 4.0 |
| S9 | ACS microdata, IPUMS USA (validation) | IPUMS USA terms of use, aggregates only |
| S10 | INEGI census data (Supplementary Information) | Términos de Libre Uso del INEGI |
| S11 | IBGE census data (Supplementary Information) | Public IBGE data |
| S12 | TechSlides country capitals (validation) | No license applicable |
| S13 | US Census Bureau: ACS 5-year tables by census tract and tract boundaries (Supplementary Information) | Public domain (CC0) |

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

**Source and licence.** TechSlides (2013), *List of Countries and Capitals*,
http://techslides.com/list-of-countries-and-capitals. No license applicable:
the file is a compilation of factual country and capital names that was
published without a licence. It is used only to build the capital indicator of
the Technical Validation and is not part of the deposited dataset.

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

---

## `census_mexico/mexico_census_inequality_epoch_ucdb2024.csv`

One row per urban centre-epoch of the epoch dataset (2010, 2015, 2020) that
contains at least one locality of 50,000 inhabitants or more. Built by
`src/06_supplementary/01_mexico_census_inequality.R`.

| Column | |
|---|---|
| `city_id_epoch_ucdb2024` | Urban centre (key of the epoch dataset) |
| `year` | Census year |
| `state_code` | INEGI state code of the urban centre's most populous large locality |
| `n_localities` | Large localities pooled in the urban centre |
| `n_households` | Sample households (unweighted) |
| `gini_census`, `theil_census` | Inequality of household income from work (`INGTRHOG`), weighted by `FACTOR` |

**Source and terms.** INEGI, Censo de Población y Vivienda 2010 and 2020
(muestra censal), Encuesta Intercensal 2015, and ITER 2020 (locality
coordinates). The indices are computed by the authors from the public
microdata; they are not official INEGI statistics. INEGI's *Términos de Libre
Uso de la Información* allow copying, redistributing and adapting its
information, provided INEGI is credited as the source and transformations are
not presented as INEGI's own (https://www.inegi.org.mx/inegi/terminos.html).

**Rebuilding.** Download the household (vivienda) files of the census samples
and the ITER 2020 from https://www.inegi.org.mx/programas/ccpv/2020/,
https://www.inegi.org.mx/programas/ccpv/2010/ and
https://www.inegi.org.mx/programas/intercensal/2015/, laid out as described in
`config.example.R` (`DIR_CENSUS_MEXICO`).

---

## `census_brazil/`

`brazil_census_inequality_by_municipality.csv`: one row per municipality and
census year (2000, 2010), with `code_muni` (IBGE 7-digit code), `n_households`
(sample households, unweighted), and `gini_census`, `theil_census` (inequality
of total household income of private households, weighted by the sample weight).

`crosswalk_epoch_ucdb2024_municipality.csv`: for each urban centre-epoch of the
epoch dataset in Brazil (2000, 2010), the municipality that covers the largest
share of its polygon (`code_muni`), its state (`state_code`) and that share
(`share_of_polygon`). Municipal boundaries of each year from IBGE, through the
`geobr` package.

Built by `src/06_supplementary/02_brazil_census_inequality.R`.

**Source and terms.** IBGE, Censo Demográfico 2000 and 2010, microdados da
amostra, publicly downloadable without registration from
https://www.ibge.gov.br/estatisticas/sociais/populacao/9662-censo-demografico-2010.html
and the IBGE FTP server. The files here are municipal aggregates computed by the
authors, with no household records; they are not official IBGE statistics. Cite
IBGE as the source when using them.

**Rebuilding.** Place the state archives of the household sample files of each
census in `DIR_CENSUS_BRAZIL/ibge-censo2000/` and `ibge-censo2010/`. Municipal
boundaries are downloaded with `geobr` if absent.
