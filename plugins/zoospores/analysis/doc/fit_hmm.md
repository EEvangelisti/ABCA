← **[Back to plugin documentation](../../README.md)**

---

# Fit hidden Markov model

## Configuration variables

| Variable | Description | Default |
|---|---|---|
| `METRICS_DIR` | Metrics directory. | `Required` |
| `HMM_ANALYSIS_DIR` | Output directory. | `<METRICS_DIR>/hmm_analysis` |
| `DT` | Time step. | `0.22` |
| `MIN_STATES` | Minimum states. | `2` |
| `MAX_STATES` | Maximum states. | `7` |
| `INITIALIZATIONS` | Initializations. | `10` |
| `N_ITER` | EM iterations. | `500` |
| `TOL` | Tolerance. | `0.0001` |
| `COVARIANCE_TYPE` | Covariance type. | `diag` |
| `MIN_TRACK_OBSERVATIONS` | Minimum observations. | `10` |
| `ACCELERATION_SCALE` | Acceleration scale. | `100` |
| `TRANSITION_GRAPH_THRESHOLD` | Transition threshold. | `0.02` |
| `CONNECTIVITY_THRESHOLD` | Connectivity threshold. | `0.02` |
| `MINIMUM_STATE_OCCUPANCY` | Minimum occupancy. | `0.01` |
| `MINIMUM_STATE_POSTERIOR` | Minimum posterior. | `0.50` |
| `MAX_TRACKS_PLOT` | Maximum tracks. | `200` |
| `QUANTILE_COUNT` | Quantiles. | `1001` |
| `DPI` | Figure resolution. | `300` |
| `WRITE_DECODED_ALL` | Write decoded tables. | `0` |

---

← **[Back to plugin documentation](../../README.md)**
