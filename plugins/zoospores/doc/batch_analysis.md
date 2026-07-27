# Batch Trajectory Analysis

Run multiple zoospore trajectory analyses in parallel. For each index in the requested range, the script generates a configuration file from `trajectory_analysis.conf.template`, replaces the `XXX` placeholder with a zero-padded index, and launches `zoospore_trajectory_analysis.sh` while limiting the number of concurrent jobs.

## Usage

```bash
./batch_analysis.sh [OPTIONS]
```

The batch root directory must contain `trajectory_analysis.conf.template`. The main analysis script, `zoospore_trajectory_analysis.sh`, must be executable and located in the same directory as the batch script.

## Options

| Option | Default | Description |
|--------|---------|-------------|
| `-r, --root DIR` | `simul_Ppar100_100_HMM/simulated_trajectories_resampled` | Batch root directory containing `trajectory_analysis.conf.template`. Relative paths are interpreted from the current working directory. |
| `-f, --first-index N` | `1` | First analysis index, inclusive. |
| `-l, --last-index N` | `100` | Last analysis index, inclusive. |
| `-j, --max-jobs N` | `10` | Maximum number of analyses executed concurrently. |
| `-h, --help` | — | Display the help message and exit. |
