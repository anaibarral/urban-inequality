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

Table 4 reports **conventional (i.i.d.) standard errors**, and so does the
reported column here, so the two agree exactly. The 1995 DMSP cell is the
reference point: 0.0190, the 0.019 printed in the manuscript.

`feols(y ~ capital | country_name)` with no `vcov` argument returns i.i.d.
errors — not cluster-by-first-fixed-effect, which is easy to assume it does.
That default produced the published numbers; the script now passes
`vcov = "iid"` explicitly so the choice is visible in the code rather than
inherited silently.

The country-clustered errors are computed alongside and written to the same CSV
as a robustness check, since cities within a country share shocks to
electrification, reporting practice and grid coverage:

| Column | Meaning |
|---|---|
| `coefficient`, `std_error` | i.i.d. Printed in Table 4 |
| `se_clustered_robustness`, `stars_clustered_robustness` | Clustered by country |

Clustering widens the errors by about 1.3× at the median. Every coefficient
stays negative and significant at 5%; two of eight cells move from *** to **
(DMSP 1995 and 2010). The note under Table 4 in the manuscript reports this.

## Coverage of the capital flag

On the current reference list the join matches **165 capitals across 163 of 182
countries**. Two problems are known:

**19 countries match no capital at all**, so their actual capital enters Table 4
as a control. The cause is a naming convention: the UCDB stores a main name with
a bracketed alternative, and the exact match fails against a plain reference
list.

| Country | Reference list | UCDB name |
|---|---|---|
| India | `new delhi` | `Delhi [New Delhi]` |
| Pakistan | `islamabad` | `Rawalpindi [Islamabad]` |
| Bolivia | `la paz` | `El Alto [La Paz]` |
| Kazakhstan | `astana` | `Nur-Sultan` |
| Myanmar | `rangoon` | `Yangon` |

India matters most: it contributes 3,192 cities, more than any other country,
and none of them is flagged as a capital. Australia, Israel, Bhutan and the
Philippines find no close match at all and need checking individually.

**Two countries match more than one capital.** Tanzania matches twice because
the UCDB contains both `Dar es Salaam` and `DAR ES SALAAM` as separate records;
after lowercasing, both hit the reference list. Nigeria has the same pattern.

None of this is introduced here: the original code used the same matching logic
and produced the same flag. A fix would extend the match to the bracketed
alternative name and de-duplicate the UCDB on a case-insensitive key, then
re-estimate Table 4.

## One further limitation, stated in the paper

**Capital status is time-invariant.** A country that relocated its capital
during 1995–2020 is coded at its current capital throughout.
