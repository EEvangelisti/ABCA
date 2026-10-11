# Cycle 3 fitting report

## Status and scope

**Success; frozen for handoff.** Model ID: `C3-CAN-BALLISTIC-ANGULAR-JITTER-01`. Before selection, `fitting/` was clear and Cycle 1 and Cycle 2 archives passed complete `sha256sum -c SHA256SUMS` checks. `select_training.sh` was executed exactly once at `2026-10-10T15:19:58Z`; no replacement selection occurred. Only these five Cycle 3 XMLs were read. No evaluation, validation, historical-trajectory, external-test, or evaluation-workspace data were used; evaluation code was unchanged.

## Selected data (`min_spots=10`)

Manifest SHA-256: `efd05a18a2415bbb4f5ba22e9f3e1f85b8e9a4bd5718b092d4993d7d55ea7737`.

| subset | SHA-256 | tracks | positions | steps | turns |
|---|---|---:|---:|---:|---:|
| subset_001.xml | `1de4a2dba815c3576e19b3effe904cc051704966442b685fbc5125c68b64340f` | 94 | 2517 | 2423 | 2329 |
| subset_007.xml | `074d4d2d883cd79938978360ff2fd3a28e311710922c5c5d6dcc420724308f68` | 90 | 2438 | 2348 | 2258 |
| subset_038.xml | `7286de70c311f17c43561e340b8316a08f4cca18243b09d09d52bc57c2768964` | 92 | 2492 | 2400 | 2308 |
| subset_079.xml | `a9833b20771dc29e93fecf43830c492c04b636cb29b73a4037b03eac86d8b8dc` | 93 | 2403 | 2310 | 2217 |
| subset_089.xml | `156f128b9f5a43dbc299e96d2d5b22e6f15d5fdfe0d0314e472fa76050cda95d` | 93 | 2487 | 2394 | 2301 |
| **total** | | **462** | **12337** | **11875** | **11413** |

The available canonical fitter parser was reused with its default `min_spots=4` explicitly overridden to 10: finite x/y, sorted time, complete consecutive frames. All files report `dt_sec=0.0700506`.

## Compatibility, units, objective, and result

The exact plugin's strict section accepts only `step_mean_um`, `step_sd_um`, and `sigma_theta_rad_per_step`. One generation is one step; steps are µm/frame and angular jitter is radians/step, with no `dt_sec` rescaling. Unknown or missing keys are rejected.

The aggregate objective is the mean of six squared, standard-error-standardized training residuals: step mean, step SD, turn mean, turn SD, mean absolute turn, and mean cosine turn. Parent step mean/SD are pooled closed-form estimates. Child angular predictions use deterministic 256-point quadrature for the exact normal conditioned on ±3 sigma. Sigma uses deterministic bounded scalar minimization plus a dense grid check; no fitting RNG is used.

Bounds: `step_mean_um>0`, `step_sd_um>=0`, and requested `sigma_theta_rad_per_step in [0.02,0.20]`.

| parameter | frozen value |
|---|---:|
| step_mean_um | 13.943062982176572 |
| step_sd_um | 5.084535951824635 |
| sigma_theta_rad_per_step | 0.2 |

Total/estimated parameter count: 3/3. Objective at freeze: 2147.338822868584. The continuous optimizer approached 0.1999999946084026 and the grid selected exactly 0.2, so the strict freeze uses the bound exactly.

**Identifiability/mismatch:** sigma is upper-bound limited. The four angular summaries are correlated and all prefer more angular variation than the permitted child can provide; standardized components for turn SD, mean absolute turn, and mean cosine are large. Aggregate SEs ignore within-track dependence. Step moments are independently well identified. No optimizer failure occurred. Numerical runtime required local BLAS/LAPACK symlinks under `fitting/lib`; system and evaluation files were not changed.

## Freeze and exact-plugin smoke

Frozen TOML: `/refinement/fitting/parameters.toml`; SHA-256 `885b2c51a7ba5051776f4688211b5fac9537b5bcb9c88e9eb56408659ddbeec7`. Fit script SHA-256: `453863c25c7fcd9f68734fbc5d6e3f24461cf853525287be2bda2f97540ddbc9`. The registered exact model was smoke-run through `run_simulation.sh` with `N_RUNS=1 START_SEED=42`. Build, simulation, and XML export succeeded; smoke XML SHA-256: `fa4ec6bc89177eff252e0f5dca821589239c9ec64eb848b852d5579b7427bfa7`. The wrapper's copied TOML hash equals the frozen hash.

## Handoff

Authorized operator should now run exactly:

```bash
cd /refinement
./run_simulation.sh C3-CAN-BALLISTIC-ANGULAR-JITTER-01 fitting/parameters.toml
```

This produces five XMLs with default seeds 1–5. Do not select again. Archive Cycle 3 training XMLs and manifest only after successful production handoff.
