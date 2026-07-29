<p align="center">
  <img src="examples/P_nicotianae_empirical.gif"
       alt="Phytophthora nicotianae zoospore simulation"
       width="400">
</p>

# Zoospore Analysis Plugin

This plugin provides a complete workflow for analysing zoospore swimming trajectories from time-lapse microscopy data. It combines image preprocessing, automated trajectory reconstruction, quantitative trajectory analysis, empirical parameter extraction for ABCA modelling, and hidden Markov model (HMM) inference.


## Available models

Two complementary behavioural models are currently supported.

- **Empirical SLOW/FAST model**: a two-state empirical model describing alternating FAST and SLOW swimming phases. Model parameters are estimated directly from experimental trajectories and exported for use by the ABCA simulator.

- **Two-state hidden Markov model**: a probabilistic hidden Markov model inferred directly from trajectory data. The HMM provides an independent statistical description of behavioural states and serves both for biological interpretation and for validating the empirical SLOW/FAST model.

## Analysis workflow

A typical analysis workflow is organised as follows:

**Trajectory analysis**
- [Setting up the Python environment](setup/README.md)
- [Extracting trajectory metrics](trajectory_analysis/metrics_extraction/README.md)
- [Analysing trajectory metrics](trajectory_analysis/metrics_analysis/README.md)
- [Plotting trajectory overviews](trajectory_analysis/plotting_overviews/README.md)
- [Analysing SLOW/FAST hysteresis](trajectory_analysis/hysteresis/README.md)

**Model fitting**
- [Extracting empirical model parameters](model_fitting/local_parameter_extraction/README.md)
- [Fitting Hidden Markov models](trajectory_analysis/hmm_model_fit/README.md)

**Model validation**
- [Resampling trajectories](model_validation/trajectory_resampling/README.md)
- [Validating simulations](model_validation/simulation_validation/README.md)

## Examples

The following files illustrate how to run simulations.

| File                                                                | Description                                     |
| ------------------------------------------------------------------- | ----------------------------------------------- |
| [`empirical.sh`](examples/empirical.sh)                             | Example of simulation using the empirical model |
| [`batch_empirical.sh`](examples/batch_empirical.sh)                 | Same as above, but for batch processing         |
| [`hmm.sh`](examples/hmm.sh)                                         | Example of simulation using the two-state HMM   |
| [`batch_hmm.sh`](examples/batch_hmm.sh)                             | Same as above, but for batch processing         |
| [`P_nicotianae_empirical.gif`](examples/P_nicotianae_empirical.gif) | Zoospore simulation using the empirical model   |
| [`P_nicotianae_hmm.gif`](examples/P_nicotianae_hmm.gif)             | Zoospore simulation using the two-state HMM     |

