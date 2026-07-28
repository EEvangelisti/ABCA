# Zoospore trajectory analysis

This directory contains the complete analysis pipeline used to quantify, analyse and model zoospore swimming behaviour for the ABCA framework.

Starting from TrackMate trajectory reconstructions, the pipeline extracts trajectory descriptors, generates publication-quality figures, estimates empirical behavioural models, and fits Hidden Markov Models (HMMs) suitable for direct integration into the ABCA simulation plugins.

Each analysis module consists of:

- a Python script implementing the scientific analysis;
- a Bash wrapper for reproducible execution;
- a configuration file containing all user-adjustable parameters;
- a dedicated README describing the module in detail.

---

## Workflow

```
TrackMate trajectories
        │
        ▼
extract_trajectory_metrics
        │
        ▼
analyse_trajectory_metrics
        │
        ├────────► plot_trajectory_overview
        ├────────► analyse_hysteresis
        ├────────► extract_local_parameters
        └────────► fit_hidden_markov_models
```

---

## Analysis modules

| Module | Description |
|---------|-------------|
| [`setup_python.md`](setup_python.md) | Configure the Python interpreter used by the analysis pipeline. |
| [`extract_trajectory_metrics.md`](extract_trajectory_metrics.md) | Extract local and global trajectory metrics from TrackMate outputs. |
| [`analyse_trajectory_metrics.md`](analyse_trajectory_metrics.md) | Generate descriptive statistics and publication-quality figures. |
| [`plot_trajectory_overview.md`](plot_trajectory_overview.md) | Produce trajectory visualisations and exploratory summaries. |
| [`analyse_hysteresis.md`](analyse_hysteresis.md) | Evaluate the influence of FAST/SLOW hysteresis thresholds. |
| [`extract_local_parameters.md`](extract_local_parameters.md) | Estimate the empirical ABCA model parameters from experimental data. |
| [`fit_hidden_markov_models.md`](fit_hidden_markov_models.md) | Fit, compare and interpret Gaussian Hidden Markov Models. |

---

## Typical workflow

```bash
./setup_python.sh

./extract_trajectory_metrics.sh extract_trajectory_metrics.conf

./analyse_trajectory_metrics.sh analyse_trajectory_metrics.conf

./plot_trajectory_overview.sh plot_trajectory_overview.conf

./analyse_hysteresis.sh analyse_hysteresis.conf

./extract_local_parameters.sh extract_local_parameters.conf

./fit_hidden_markov_models.sh fit_hidden_markov_models.conf
```

---

## Outputs

The pipeline produces:

- trajectory metrics;
- publication-quality figures;
- empirical behavioural models;
- ABCA parameter tables;
- Hidden Markov Models;
- HMM parameter tables compatible with the ABCA simulation plugins.
