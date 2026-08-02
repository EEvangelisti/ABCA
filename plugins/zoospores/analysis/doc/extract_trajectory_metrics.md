← **[Back to plugin documentation](../../README.md)**

---

# Extract Trajectory Metrics

## Configuration variables

| Variable | Description | Default |
|---|---|---|
| `XML_SOURCE` | Directory containing TrackMate XML files. | `Required` |
| `OUTPUT_DIR` | Output directory. | `Required` |
| `FRAME_INTERVAL_S` | Time interval between frames (s). | `0.22` |
| `COORD_SCALE` | Coordinate scaling factor. | `1` |
| `SPATIAL_UNIT` | Spatial unit. | `micron` |
| `MIN_SPOTS` | Minimum spots. | `10` |
| `DIRECTION_THRESHOLD_DEG` | Direction threshold (deg). | `30` |
| `MAX_LAG` | Maximum lag. | `25` |
| `LENGTH_FILTER_MODE` | percentile|max_points|none | `percentile` |
| `LENGTH_FILTER_PERCENTILE` | Upper percentile. | `90` |
| `LENGTH_FILTER_MAX_POINTS` | Maximum points. | `0` |
| `FILTERED_SUBDIR` | Filtered output subdirectory. | `length_filtered` |

---

← **[Back to plugin documentation](../../README.md)**
