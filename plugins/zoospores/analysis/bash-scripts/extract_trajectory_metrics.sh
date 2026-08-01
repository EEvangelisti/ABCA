#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$ROOT/utils.sh"

initialize_environment "$ROOT" "extract_trajectory_metrics.py" "$@"

# ------------------------------------------------------------------------------

require_variables PYTHON PYTHON_SCRIPT XML_SOURCE OUTPUT_DIR
require_directory "$XML_SOURCE" "XML source directory"

# Time interval between two consecutive frames (s).
FRAME_INTERVAL_S="${FRAME_INTERVAL_S:-0.22}"
require_number FRAME_INTERVAL_S positive

# Spatial scaling factor applied to trajectory coordinates.
COORD_SCALE="${COORD_SCALE:-1}"
require_number COORD_SCALE positive

# Spatial unit used in the output files.
SPATIAL_UNIT="${SPATIAL_UNIT:-micron}"

# Minimum number of spots required per trajectory.
MIN_SPOTS="${MIN_SPOTS:-10}"
require_integer MIN_SPOTS positive

# Direction-change threshold for behavioural metrics (degrees).
DIRECTION_THRESHOLD_DEG="${DIRECTION_THRESHOLD_DEG:-30}"
require_number DIRECTION_THRESHOLD_DEG non-negative

# Maximum lag used for time-lag analyses.
MAX_LAG="${MAX_LAG:-25}"
require_integer MAX_LAG positive

# Trajectory length filtering mode.
LENGTH_FILTER_MODE="${LENGTH_FILTER_MODE:-percentile}"
require_choice LENGTH_FILTER_MODE percentile max_points none

# Upper percentile retained when filtering by percentile.
LENGTH_FILTER_PERCENTILE="${LENGTH_FILTER_PERCENTILE:-90}"

# Maximum trajectory length retained when filtering by point count.
LENGTH_FILTER_MAX_POINTS="${LENGTH_FILTER_MAX_POINTS:-0}"

# Name of the directory containing filtered outputs.
FILTERED_SUBDIR="${FILTERED_SUBDIR:-length_filtered}"

args=(
    "$XML_SOURCE"
    --outdir "$OUTPUT_DIR"
    --dt "$FRAME_INTERVAL_S"
    --coord-scale "$COORD_SCALE"
    --unit "$SPATIAL_UNIT"
    --min-spots "$MIN_SPOTS"
    --direction-threshold-deg "$DIRECTION_THRESHOLD_DEG"
    --max-lag "$MAX_LAG"
)

case "$LENGTH_FILTER_MODE" in
    percentile)
        require_integer LENGTH_FILTER_PERCENTILE ">" 0 "<=" 100

        args+=(
            --length-filter-percentile "$LENGTH_FILTER_PERCENTILE"
            --filtered-subdir "$FILTERED_SUBDIR"
        )
        ;;

    max_points)
        require_integer LENGTH_FILTER_MAX_POINTS positive

        args+=(
            --length-filter-max-points "$LENGTH_FILTER_MAX_POINTS"
            --filtered-subdir "$FILTERED_SUBDIR"
        )
        ;;

    none)
        args+=(--no-length-filter)
        ;;
esac

mkdir -p "$OUTPUT_DIR"

cat <<EOF
Extracting trajectory metrics
=============================
XML source: $XML_SOURCE
Output:     $OUTPUT_DIR

EOF

"$PYTHON" "$PYTHON_SCRIPT" "${args[@]}"

job_done "Trajectory metric extraction completed"
