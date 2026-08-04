# Case study 1 — Capital cities

Do national capitals have steeper centre-periphery luminosity gradients than
other cities in the same country? Produces **Table 4**.

| Step | Script | Produces |
|---|---|---|
| 1 | `01_build_capital_panel.R` | `capital_panel.parquet` — the dataset with a capital indicator |
| 2 | `table_04_capital_gradients.R` | Table 4, plus coefficient plots and residual densities |

```bash
Rscript src/03_case_study_capitals/01_build_capital_panel.R
Rscript src/03_case_study_capitals/table_04_capital_gradients.R
```

## Specification

For each benchmark year and NTL source, separately:

```
beta_i = alpha + theta * Capital_i + gamma_c(i) + e_i
```

`beta_i` is the population-controlled gradient of city *i*, `Capital_i` the
indicator, `gamma_c(i)` country fixed effects, standard errors clustered by
country.

The country fixed effect is the point of the design. Capitals sit in richer and
more electrified countries on average, so an unconditional comparison would
mostly recover cross-country differences. Absorbing the country makes `theta` a
comparison of a capital against other cities in the same country.

This is also why N is smaller than the count of estimable gradients: countries
represented by a single urban centre carry no within-country variation and are
absorbed entirely, so `fixest` drops them.

## What the identification does and does not support

The exercise is a **validation check, not a causal estimate**. It asks whether
the gradient measure recovers a structural difference that urban economics
predicts independently. It finds one — capitals are steeper in every year and
both sources — which is evidence that the measure captures spatial organisation
rather than noise. It says nothing about why, and the design cannot separate
administrative function from the size, age and planning history that capitals
also tend to share.

## Standard errors

Standard errors are **clustered at the country level**, matching Table 4. Cities
within a country share shocks to electrification, reporting practice and grid
coverage, so residuals are not independent within the fixed effect being
absorbed. Each yearly regression uses 155 to 157 clusters, well above the range
where the clustered variance estimator becomes unreliable.

`cluster = ~ country_name` is passed explicitly in every call.

The i.i.d. errors are computed alongside and written to the same CSV as a
reference:

| Column | Meaning |
|---|---|
| `coefficient`, `std_error` | Clustered by country. As reported in Table 4 |
| `se_iid_reference`, `stars_iid_reference` | i.i.d. |

Coefficients are identical under either estimator — clustering changes only the
variance. It widens the errors by about 1.3× at the median, from 1.06× to 1.41×.
Every coefficient stays negative and significant at 5%; two of the eight cells
sit at the 5% rather than the 1% level (DMSP 1995 and 2010).

## Coverage of the capital flag

The join matches **165 capitals across 163 of 182 countries**. Coverage is
bounded by how the two sources spell city names.

The UCDB sometimes stores a main name with a bracketed alternative — `Delhi
[New Delhi]`, `Rawalpindi [Islamabad]`, `El Alto [La Paz]` — and sometimes uses
a different transliteration or a more recent renaming than a plain reference
list carries, as with `Nur-Sultan` for Astana or `Yangon` for Rangoon. An exact
match on the normalised name does not resolve those, and the city is treated as
a non-capital. Extending the match to the bracketed alternative would recover
most of them.

A small number of UCDB records also differ only in capitalisation, so a
lowercased key can match the same capital twice within a country.

## Capital status is time-invariant

A country that relocated its capital during 1995–2020 is coded at its current
capital throughout, as stated in the paper.
