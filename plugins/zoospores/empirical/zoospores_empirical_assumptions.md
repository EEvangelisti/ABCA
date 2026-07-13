# Empirical zoospore plugin: modelling assumptions

## What is read from the CSV

The plugin reads only **local quantities**:

- acquisition time step;
- initial RUN/STOP occupancy;
- one-step RUN/STOP transition probabilities;
- state-conditional speed quantiles;
- speed lag-1 correlation;
- absolute turning-angle quantiles;
- directional memory time;
- speed–turn coupling;
- acceleration quantiles, used only as a numerical guard.

MSD, straightness, tortuosity, path length and net displacement are never used as rules. They remain validation outputs.

## Why CSV rather than JSON

CSV avoids adding a JSON library to the current `dune` stanza. The parser is embedded in the plugin and reads the existing `parameter,value` columns directly.

## Distribution choices

### Initial population

Initial RUN/STOP states, headings and latent speed ranks are assigned by **stratified sampling** and then shuffled. With many agents, this gives the requested population fractions and marginal distributions more faithfully than independent random draws, while preserving random spatial assignment.

### Speed distribution

The empirical distributions are visibly non-normal and only summary quantiles are available. The plugin therefore does **not** fit a Gaussian, gamma or log-normal distribution.

It builds a piecewise-linear inverse CDF through:

`q10, q25, median, q75, q90`

and extrapolates conservative endpoints. This is a quantile distribution: it retains skewness without claiming a parametric family unsupported by the available CSV.

Temporal speed persistence is represented with a **Gaussian copula AR(1)** using the measured lag-1 correlation. The copula supplies dependence; the inverse empirical quantile function supplies the non-normal marginal distribution.

### Turning angle

Absolute turning angles are sampled from the same type of piecewise-linear quantile distribution. The measured negative speed–turn correlation enters through a Gaussian copula: faster agents tend to receive smaller directional changes.

The turn innovation also has an AR(1) memory coefficient derived from:

`exp(-dt / direction_memory_1_over_e_time)`.

The signed median is close to zero and the data file does not estimate a stable left/right probability. The sign is therefore sampled symmetrically. This deliberately assumes no intrinsic handedness.

### Acceleration

Acceleration is not independently sampled because that would compete with the empirically constrained speed distribution and speed autocorrelation. Instead, the proposed speed change is winsorised at a generous multiple of the empirical absolute-acceleration q90. The default multiplier is 3 and can be changed through `ACCEL_CAP_MULTIPLIER`.

This is a numerical safeguard, not a global trajectory rule.

## Spatial assumptions

- Agent positions are continuous.
- `MICRONS_PER_CELL` converts physical displacement into display-grid displacement.
- Two agents may occupy the same display cell because a cell is only a rendering bin; no measured zoospore–zoospore exclusion law was supplied.
- Toroidal boundaries wrap continuously.
- Bounded walls cause deterministic specular reflection. This is an environmental boundary rule, not inferred swimming biology.
- Initial geometry and agent number remain run-time setup parameters, not biological movement parameters.

## Main command-line plugin arguments

- `PARAMS=/path/to/abca_local_parameters.csv`
- `MICRONS_PER_CELL=10`
- `INIT=FULL|DISK|RING`
- `RADIUS=60`
- `THICKNESS=4`
- `ACCEL_CAP_MULTIPLIER=3`
- `MAX_AGE=255`

Example:

```bash
abca --mode run \
  --model zoospores-empirical \
  --rows 300 --cols 300 \
  --generations 500 \
  --agents 1000 \
  --seed 42 \
  --plugin-arg PARAMS=plugins/zoospores/abca_local_parameters.csv \
  --plugin-arg MICRONS_PER_CELL=10 \
  --plugin-arg INIT=FULL \
  --out zoospores_empirical.bin
```
