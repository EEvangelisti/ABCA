# Trajectory analysis

## Setting up the Python environment

### Purpose

Create a dedicated Python virtual environment, install all required Python
packages, and generate a `python.conf` configuration file for subsequent
analysis scripts.

### Input

- Python interpreter (optional command-line argument; default: `/usr/bin/env python3`)

### Output

- Python virtual environment (`python_venv/`)
- Configuration file (`python.conf`) containing the path to the Python
  interpreter inside the virtual environment

### Usage

```bash
./setup_python.sh
```

or

```bash
./setup_python.sh /path/to/python3
```

### Notes

- The virtual environment is created only if it does not already exist.
- Required Python packages are installed or upgraded automatically.
- Other Bash scripts in the workflow read `python.conf` to locate the Python
  interpreter, ensuring that the same environment is used throughout the
  analysis pipeline.

## 1. Metrics extraction

## 2. Metrics analysis

## 3. Trajectory overview plots

## 4. Hysteresis analysis

## 5. ABCA parameters

## 6. HMM analysis

## 7. Resampling simulated trajectories

### Purpose

Resample simulated ABCA trajectories to match the distribution of trajectory
lengths in an experimental dataset. The script extracts random contiguous
segments from sufficiently long simulated trajectories while preserving their
local dynamics.

### Input

- `resample.conf` (configuration file)
- TrackMate-compatible XML trajectory files
- CSV file containing empirical trajectory lengths

### Output

For each input XML file:

- resampled XML trajectory file;
- resampling provenance table (`*_resampling_provenance.csv`);
- sampled trajectory lengths (`*_sampled_lengths.csv`).

### Usage

```bash
./resample.sh
```

### Notes

- Multiple XML files are processed in parallel.
- The maximum number of concurrent jobs is defined in `resample.conf`.
- The random seed is incremented automatically for successive files.
