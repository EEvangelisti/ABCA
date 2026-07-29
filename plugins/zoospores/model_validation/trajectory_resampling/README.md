← **[Back to plugin documentation](../../README.md)**

---

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

### A typical output

```
Trajectory resampling
=====================
Python interpreter:    /home/user/setup/python_venv/bin/python
Configuration file:    resample_trajectories.conf
Input directory:       ../../tracks
Output directory:      ../../output/resampled
Empirical lengths:     /home/experiment/trajectory_analysis/trajectory_overview/03_trajectory_lengths_filtered.csv
XML files:             1
Maximum parallel jobs: 5
Initial random seed:   1

[1/1] Resampling P_nicotianae_hmm_000042.xml (seed=1)...
Resampling completed.
  Source particles: 2500
  Longest source trajectory: 101 points
  Empirical lengths available: 58696
  Output particles: 58696
  Output detections: 1854365
  Sampled median length: 28 points
  Sampled range: 11-73 points
  XML: ../../output/resampled/P_nicotianae_hmm_000042.xml
  Provenance: ../../output/resampled/P_nicotianae_hmm_000042_resampling_provenance.csv
  Sampled lengths: ../../output/resampled/P_nicotianae_hmm_000042_sampled_lengths.csv
[1/1] Completed P_nicotianae_hmm_000042.xml.

All resampling jobs completed.
```

### Notes

- Multiple XML files are processed in parallel.
- The maximum number of concurrent jobs is defined in `resample.conf`.
- The random seed is incremented automatically for successive files.

---

← **[Back to plugin documentation](../../README.md)**
