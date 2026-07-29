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

### Notes

- Multiple XML files are processed in parallel.
- The maximum number of concurrent jobs is defined in `resample.conf`.
- The random seed is incremented automatically for successive files.

---

← **[Back to plugin documentation](../../README.md)**
