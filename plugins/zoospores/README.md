← **[Back to ABCA documentation](../../README.md)**

---

# Modelling Zoospore Swimming Behaviour

This repository provides two behavioural models of zoospore swimming calibrated 
from nearly 60,000 experimentally reconstructed trajectories of 
*Phytophthora nicotianae* zoospores freely exploring a liquid environment. 
The models comprise an empirical SLOW/FAST model and a hidden Markov model 
(HMM), which can be directly used with the ABCA simulation framework.

To facilitate the development of new behavioural models, the complete analysis 
workflow used for model calibration is also provided. It includes image 
preprocessing, automated trajectory reconstruction, quantitative trajectory 
analysis, empirical parameter extraction, and HMM inference, allowing users 
to infer equivalent models from their own time-lapse microscopy datasets.

<p align="center">
  <a href="examples/P_nicotianae_empirical.gif">
    <img src="examples/P_nicotianae_empirical.gif" alt="Speed distribution" width="400">
  </a>
  <a href="examples/02_centered_trajectories.png">
    <img src="examples/02_centered_trajectories.png" width="400">
  </a>
</p>
<p align="center"><em>Click any image to view it at full resolution.</em></p>

## Available models

Three complementary behavioural models are currently provided.

- **Empirical SLOW/FAST model**: a two-state empirical model describing
  alternating SLOW and FAST swimming phases. Its parameters were estimated
  directly from experimentally reconstructed trajectories and exported for use
  with the ABCA simulation framework.

- **Empirical SLOW/FAST model with beads**: an extension of the empirical
  model that incorporates static circular obstacles representing experimental
  beads. Several collision-response mechanisms are available (tangential
  sliding, contact slowdown, or a combination of both), allowing the model to
  predict zoospore behaviour in geometrically constrained environments without
  modifying the underlying behavioural parameters.

- **Two-state hidden Markov model (HMM)**: a probabilistic model inferred
  independently from the same trajectory dataset. It provides an alternative
  statistical description of zoospore behaviour and serves both to refine the
  biological interpretation of swimming states and to independently validate
  the empirical SLOW/FAST model.


# Collision-response modes

The plugin now supports three values for `COLLISION_RESPONSE`:

- `TANGENT`: remove the inward normal component and retain the complete
  tangential projection.
- `SLOWDOWN`: stop at the first bead contact during the current simulation
  step.
- `BOTH`: retain tangential motion and multiply the remaining tangential
  displacement by `COLLISION_SLOWDOWN`.

`COLLISION_SLOWDOWN` is a number in `[0,1]` and defaults to `0.5`.
It is only used in `BOTH` mode.

Examples:

```text
COLLISION_RESPONSE=TANGENT
```

```text
COLLISION_RESPONSE=SLOWDOWN
```

```text
COLLISION_RESPONSE=BOTH
COLLISION_SLOWDOWN=0.25
```


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
[set up the shared Python environment](analysis/setup/README.md).
Each analysis module is configured through a dedicated configuration file stored 
in a common configuration directory and can be executed independently using the 
generic run launcher:

```
./run <command> <configuration_directory>
```

where `<command>` specifies the analysis step (e.g. extract, analyse, plot, 
hysteresis, local_parameters, hmm, resample, validate, or compare). This design 
provides a consistent interface across the entire workflow while allowing users 
to inspect and modify the configuration files before each analysis stage.

> [!NOTE]
> **Trajectory reconstruction.** Before the analysis workflow can be applied, 
zoospore trajectories must first be reconstructed from time-lapse microscopy 
image series. This is typically achieved using ImageJ/Fiji together with a 
dedicated particle-tracking plugin such as
[TrackMate](https://imagej.net/plugins/trackmate/). A typical workflow consists 
of (1) image preprocessing (e.g. background subtraction, size filtering, and 
noise reduction), (2) particle detection, and (3) trajectory reconstruction by 
linking detections across successive frames.


### Trajectory analysis

These modules extract quantitative descriptors from reconstructed trajectories 
and generate the figures and summary statistics used to characterise zoospore 
swimming behaviour.

| Command                    | Description                 | Configuration file                                               |
| -------------------------- | --------------------------- | ---------------------------------------------------------------- |
| `run extract <CONFIG_DIR>` | Extract trajectory metrics. | [Configuration](analysis/config/extract_trajectory_metrics.conf) |
| `run analyse <CONFIG_DIR>` | Analyse trajectory metrics. | [Configuration](analysis/config/analyse_trajectory_metrics.conf) |
| `run plot <CONFIG_DIR>`    | Plot trajectory overviews.  | [Configuration](analysis/config/plot_trajectory_overview.conf)   |

> [!NOTE]
> **Convenience wrappers.** The command `analyse_trajectories <CONFIG_DIR>` runs 
the complete trajectory-analysis workflow (metric extraction, metric analysis, 
and overview plotting) from a single configuration directory. The companion 
script `batch_analyse_trajectories` performs the same workflow in parallel for 
multiple independent datasets by generating a dedicated configuration directory 
for each analysis. Since every dataset produces its own complete set of outputs, 
large batch analyses may require substantial disk space.

<h4 align="center">Representative outputs</h4>

<p align="center">
  <a href="examples/01_speed_distribution.png"><img src="examples/01_speed_distribution.png" alt="Speed distribution" width="45%"></a>
  <a href="examples/04_net_displacement.png"><img src="examples/04_net_displacement.png" alt="Net displacement" width="45%"></a>
</p>
<p align="center"><em>Click any image to view it at full resolution.</em></p>

### Model fitting

These modules infer empirical and Hidden Markov behavioural models directly 
from the experimental data, producing parameter sets compatible with the ABCA 
simulation framework.

| Command                             | Description                         | Configuration file                                                   |
| ----------------------------------- | ----------------------------------- | -------------------------------------------------------------------- |
| `run hysteresis <CONFIG_DIR>`       | Analyse SLOW/FAST hysteresis.       | [Configuration](analysis/config/analyse_hysteresis.conf)             |
| `run local_parameters <CONFIG_DIR>` | Extract empirical model parameters. | [Configuration](analysis/config/extract_local_parameters.conf)       |
| `run hmm <CONFIG_DIR>`              | Fit hidden Markov models.           | [Configuration](analysis/config/fit_and_interpret_zoospore_hmm.conf) |

At this stage, you can run simulations using your own input files. For examples of Bash scripts, see above.

### Model validation

These modules compare simulated and experimental trajectories after controlling 
for differences in trajectory length, allowing quantitative validation of 
simulation outputs.

| Command                     | Description                                          | Configuration file                                          |
| --------------------------- | ---------------------------------------------------- | ----------------------------------------------------------- |
| `run resample <CONFIG_DIR>` | Resample trajectories.                               | [Configuration](analysis/config/resample_trajectories.conf) |
| `run burn_in <CONFIG_DIR>`  | Remove an initial burn-in period from trajectories.  | [Configuration](analysis/config/apply_burn_in.conf)  |
| `run validate <CONFIG_DIR>` | Validate simulations using global metrics.           | [Configuration](analysis/config/validate_simulations.conf)  |
| `run compare <CONFIG_DIR>`  | Compare model performance against experimental data. | [Configuration](analysis/config/compare_models.conf)        |

Predictive validation can then be performed by applying the same workflow to 
independent experimental datasets and comparing the resulting simulations with 
the corresponding observations.

<h4 align="center">Representative outputs</h4>

<p align="center">
  <a href="examples/05_absolute_acceleration_experimental_vs_simulations.png"><img src="examples/05_absolute_acceleration_experimental_vs_simulations.png" alt="Speed distribution" width="45%"></a>
  <a href="examples/06_net_displacement_experimental_vs_simulations.png"><img src="examples/06_net_displacement_experimental_vs_simulations.png" width="45%"></a>
</p>
<p align="center"><em>Click any image to view it at full resolution.</em></p>

---

← **[Back to ABCA documentation](../../README.md)**
