← **[Back to ABCA documentation](../../README.md)**

---

# Modelling Zoospore Swimming Behaviour

This plugin provides a complete workflow for analysing zoospore swimming trajectories from time-lapse microscopy data. It combines image preprocessing, automated trajectory reconstruction, quantitative trajectory analysis, empirical parameter extraction for ABCA modelling, and hidden Markov model (HMM) inference.

<p align="center">
  <img src="examples/P_nicotianae_empirical.gif"
       alt="Phytophthora nicotianae zoospore simulation"
       width="400">
</p>

## Available models

Two complementary behavioural models are currently supported.

- **Empirical SLOW/FAST model**: a two-state empirical model describing alternating FAST and SLOW swimming phases. Model parameters are estimated directly from experimental trajectories and exported for use by the ABCA simulator.

- **Two-state hidden Markov model**: a probabilistic hidden Markov model inferred directly from trajectory data. The HMM provides an independent statistical description of behavioural states and serves both for biological interpretation and for validating the empirical SLOW/FAST model.

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

## Workflow for building new behavioural models

A typical analysis workflow consists of three stages: trajectory analysis, 
model fitting, and model validation. Before running the analysis pipeline, 
[set up the Python environment](setup/README.md). This environment is shared by 
all scripts and ensures isolated, reproducible execution. For convenience, a 
[`run_all.sh`](run_all.sh) script is provided to automate the complete workflow. 
Nevertheless, users are encouraged to review and adjust the configuration files 
associated with each analysis step before launching the pipeline.

> [!IMPORTANT]
> **Directory layout.** The analysis pipeline is designed around a fixed 
directory layout in which all analysis modules are organised as sibling 
directories within a common parent directory. The relative paths used 
throughout the configuration files, shell wrappers, and the `run_all.sh` 
script assume this layout. Modifying the directory structure is not recommended. 
If you do so, the relative paths defined throughout the configuration files, 
shell wrappers, and `run_all.sh` must be updated accordingly.


### Trajectory analysis

These modules extract quantitative descriptors from reconstructed trajectories 
and generate the figures and summary statistics used to characterise zoospore 
swimming behaviour.

- [Extracting trajectory metrics](trajectory_analysis/metrics_extraction/README.md)
- [Analysing trajectory metrics](trajectory_analysis/metrics_analysis/README.md)
- [Plotting trajectory overviews](trajectory_analysis/plotting_overviews/README.md)

### Model fitting

These modules infer empirical and Hidden Markov behavioural models directly 
from the experimental data, producing parameter sets compatible with the ABCA 
simulation framework.

- [Analysing SLOW/FAST hysteresis](trajectory_analysis/hysteresis/README.md)
- [Extracting empirical model parameters](model_fitting/local_parameter_extraction/README.md)
- [Fitting Hidden Markov models](trajectory_analysis/hmm_model_fit/README.md)

### Model validation

These modules compare simulated and experimental trajectories after controlling 
for differences in trajectory length, allowing quantitative validation of 
simulation outputs.

- [Resampling trajectories](model_validation/trajectory_resampling/README.md)
- [Validating simulations](model_validation/simulation_validation/README.md)

---

← **[Back to ABCA documentation](../../README.md)**
