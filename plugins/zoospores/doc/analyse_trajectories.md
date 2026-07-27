# Trajectory Analysis Workflow

Complete analysis pipeline for zoospore trajectory datasets. The script extracts trajectory metrics from TrackMate XML files, performs statistical analyses and visualisations, prepares empirical ABCA parameters, and optionally fits hidden Markov models (HMMs).

## Usage

```bash
./zoospore_trajectory_analysis.sh CONFIG_FILE
```

The configuration file consists of `KEY=value` assignments. Any parameter defined in the configuration overrides the built-in defaults. Relative paths are interpreted relative to the configuration file location.

## Configuration reference

| Parameter | Default | Description |
|-----------|---------|-------------|
| **Input / output** |||
| `XML_SOURCE` | `tracks` | Directory containing TrackMate XML files. |
| `OUTPUT_ROOT` | `trajectory_analysis` | Root directory for all generated outputs. |
| **Python environment** |||
| `PYTHON_DIR` | `python_scripts` | Directory containing the analysis scripts. |
| `VENV_DIR` | `python_venvs/zoospore_env` | Python virtual environment. Created automatically if absent. |
| `PYTHON_COMMAND` | `/usr/bin/env python3` | Python executable used to create the virtual environment. |
| **Workflow stages** |||
| `EXTRACT_METRICS` | `1` | Extract trajectory metrics from XML files. |
| `MAKE_METRICS_PLOTS` | `1` | Generate summary plots and descriptive statistics. |
| `TEST_FAST_SLOW_HYSTERESIS` | `1` | Evaluate FAST/SLOW hysteresis thresholds. |
| `TRAJECTORY_OVERVIEW` | `1` | Produce global trajectory overview figures. |
| `EXTRACT_ABCA_PARAMETERS` | `1` | Export empirical parameters for the ABCA model. |
| `RUN_HMM` | `1` | Fit and interpret hidden Markov models. |
| **Trajectory parameters** |||
| `FRAME_INTERVAL_S` | `0.07` | Time interval between consecutive frames (s). |
| `COORD_SCALE` | `1` | Coordinate scaling factor. |
| `SPATIAL_UNIT` | `micron` | Spatial unit label used in outputs. |
| `MIN_SPOTS` | `10` | Minimum trajectory length. |
| `DIRECTION_THRESHOLD_DEG` | `30` | Direction-change threshold (degrees). |
| `MAX_LAG` | `25` | Maximum lag used for temporal statistics. |
| `DPI` | `300` | Output figure resolution. |
| **FAST/SLOW hysteresis** |||
| `HYSTERESIS_WIDTHS` | `0,5,10,15,20,30,40` | Hysteresis widths evaluated during sensitivity analysis. |
| `HYSTERESIS_OTSU_BINS` | `256` | Histogram bins for Otsu threshold estimation. |
| `HYSTERESIS_HISTOGRAM_BINS` | `50` | Histogram bins used in plots. |
| `HYSTERESIS_HALF_WIDTH` | `25` | Half-width used when exporting ABCA parameters. |
| **Trajectory overview** |||
| `ANGULAR_BINS` | `36` | Number of angular bins for directional analyses. |
| `MAX_TRACKS` | `0` | Maximum trajectories displayed (`0` = all). |
| `MAX_TRACKS_PER_DECILE` | `0` | Maximum trajectories displayed per decile (`0` = all). |
| **HMM analysis** |||
| `HMM_MIN_STATES` | `2` | Minimum number of hidden states. |
| `HMM_MAX_STATES` | `7` | Maximum number of hidden states. |
| `HMM_INITIALIZATIONS` | `10` | Random initialisations per model. |
| `HMM_COVARIANCE_TYPE` | `diag` | Covariance model used by the HMM. |
| `HMM_MIN_TRACK_OBSERVATIONS` | `10` | Minimum observations per trajectory. |
| `HMM_TRANSITION_GRAPH_THRESHOLD` | `0.02` | Minimum transition probability displayed in graphs. |
| `HMM_MAX_TRACKS_PLOT` | `200` | Maximum trajectories shown in HMM visualisations. |
| **Output** |||
| `QUIET` | `0` | Suppress progress messages when set to `1`. |
