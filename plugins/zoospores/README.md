<p align="center">
  <img src="examples/P_nicotianae_empirical.gif" alt="Phytophthora nicotianae zoospore simulation" />
</p>

# Zoospore Analysis Plugin

This plugin provides a complete workflow for analysing zoospore swimming trajectories from time-lapse microscopy data. It combines image preprocessing, automated trajectory reconstruction, quantitative trajectory analysis, empirical parameter extraction for ABCA modelling, and hidden Markov model (HMM) inference.

The workflow is organised into four successive stages:

```
Microscopy movies
        │
        ▼
 Image preprocessing
        │
        ▼
Trajectory reconstruction
    (TrackMate/Fiji)
        │
        ▼
Trajectory analysis
        │
        ├── Empirical SLOW/FAST model
        └── Two-state HMM
```

## Image preprocessing

**PLACEHOLDER**

This section will describe the preprocessing pipeline applied to raw microscopy movies before trajectory reconstruction, including image calibration, background correction, and TrackMate-compatible stack generation.

---

## Trajectory analysis

Trajectory analysis is performed using the `zoospore_trajectory_analysis.sh` workflow, which computes quantitative descriptors of zoospore swimming behaviour, generates publication-ready figures, extracts empirical parameters for ABCA simulations, and optionally fits hidden Markov models.

Detailed documentation is available in:

- [`doc/analyse_trajectories.md`](doc/analyse_trajectories.md): analysis workflow and configuration parameters.
- [`doc/batch_analysis.md`](doc/batch_analysis.md): parallel execution of multiple analyses.

---

## Behavioural models

Two complementary behavioural models are currently supported.

### Empirical SLOW/FAST model

A two-state empirical model describing alternating FAST and SLOW swimming phases. Model parameters are estimated directly from experimental trajectories and exported for use by the ABCA simulator.

### Two-state hidden Markov model

A probabilistic hidden Markov model inferred directly from trajectory data. The HMM provides an independent statistical description of behavioural states and serves both for biological interpretation and for validating the empirical SLOW/FAST model.
