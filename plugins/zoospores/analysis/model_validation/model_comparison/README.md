← **[Back to plugin documentation](../../../README.md)**

---

## Comparing behavioural models

### Purpose

Quantitatively compare multiple behavioural models against experimental
trajectory data using global descriptors of spatial exploration. The script
summarises model performance across independent simulations and reports
distribution-based metrics for net displacement together with curve-based
metrics for the mean squared displacement (MSD).

### Input

- `python.conf`
- Model-comparison configuration
- Experimental trajectory-analysis directory
- Indexed trajectory-analysis directories for each behavioural model

### Output

- Per-simulation comparison metrics
- Summary statistics across simulations
- Publication-ready comparison tables (CSV and Markdown)
- Execution log

### Usage

```bash
./compare_models.sh
```

### Notes

The wrapper supports multiple independent simulations organised as indexed
trajectory-analysis directories (e.g. `trajectory_analysis_001`,
`trajectory_analysis_002`, ...). Comparison intervals can be configured in
`compare_models.conf`, with `CI_LEVEL=100` reporting the full range across
simulations (no clipping).

---

← **[Back to plugin documentation](../../../README.md)**
