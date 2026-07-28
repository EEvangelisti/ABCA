<p align="center">
  <img src="examples/P_nicotianae_empirical.gif"
       alt="Phytophthora nicotianae zoospore simulation"
       width="400">
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

## Trajectory analysis

See the [documentation](analysis/README.md).

## Behavioural models

Two complementary behavioural models are currently supported.

### Empirical SLOW/FAST model

A two-state empirical model describing alternating FAST and SLOW swimming phases. Model parameters are estimated directly from experimental trajectories and exported for use by the ABCA simulator.

### Two-state hidden Markov model

A probabilistic hidden Markov model inferred directly from trajectory data. The HMM provides an independent statistical description of behavioural states and serves both for biological interpretation and for validating the empirical SLOW/FAST model.

## Examples

Examples can be found in [`examples`](examples/).

| File                                                                | Description                                     |
| ------------------------------------------------------------------- | ----------------------------------------------- |
| [`empirical.sh`](examples/empirical.sh)                             | Example of simulation using the empirical model |
| [`batch_empirical.sh`](examples/batch_empirical.sh)                 | Same as above, but for batch processing         |
| [`hmm.sh`](examples/hmm.sh)                                         | Example of simulation using the two-state HMM   |
| [`P_nicotianae_empirical.gif`](examples/P_nicotianae_empirical.gif) | Zoospore simulation using the empirical model   |
| [`P_nicotianae_hmm.gif`](examples/P_nicotianae_hmm.gif)             | Zoospore simulation using the two-state HMM     |

