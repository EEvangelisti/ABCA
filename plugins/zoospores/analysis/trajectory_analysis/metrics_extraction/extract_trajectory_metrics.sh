#!/usr/bin/env bash
# Extract trajectory metrics from TrackMate-compatible or ABCA XML files.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ABCA_CONFIG_DIR"
# shellcheck source=/dev/null
source "$1"

# ------------------------------------------------------------------------------
FRAME_INTERVAL_S="${FRAME_INTERVAL_S:-0.22}"
COORD_SCALE="${COORD_SCALE:-1}"
SPATIAL_UNIT="${SPATIAL_UNIT:-micron}"
MIN_SPOTS="${MIN_SPOTS:-10}"
DIRECTION_THRESHOLD_DEG="${DIRECTION_THRESHOLD_DEG:-30}"
MAX_LAG="${MAX_LAG:-25}"
LENGTH_FILTER_MODE="${LENGTH_FILTER_MODE:-percentile}"
LENGTH_FILTER_PERCENTILE="${LENGTH_FILTER_PERCENTILE:-90}"
LENGTH_FILTER_MAX_POINTS="${LENGTH_FILTER_MAX_POINTS:-0}"
FILTERED_SUBDIR="${FILTERED_SUBDIR:-length_filtered}"
# ------------------------------------------------------------------------------

filter_args=()

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

case "$LENGTH_FILTER_MODE" in
    percentile)
        filter_args=(
            --length-filter-percentile "$LENGTH_FILTER_PERCENTILE"
            --filtered-subdir "$FILTERED_SUBDIR"
        )
        ;;

    max_points)
        filter_args=(
            --length-filter-max-points "$LENGTH_FILTER_MAX_POINTS"
            --filtered-subdir "$FILTERED_SUBDIR"
        )
        ;;

    none)
        filter_args=(--no-length-filter)
        ;;

    *)
        die "Invalid LENGTH_FILTER_MODE: $LENGTH_FILTER_MODE"
        ;;
esac

mkdir -p "$OUTPUT_DIR"

echo "Extracting trajectory metrics..."
echo "  XML source: $XML_SOURCE"
echo "  Output:     $OUTPUT_DIR"
echo "  Python:     $(command -v python)"

python "$ROOT/extract_trajectory_metrics.py" \
    "$XML_SOURCE" \
    --outdir "$OUTPUT_DIR" \
    --dt "$FRAME_INTERVAL_S" \
    --coord-scale "$COORD_SCALE" \
    --unit "$SPATIAL_UNIT" \
    --min-spots "$MIN_SPOTS" \
    --direction-threshold-deg "$DIRECTION_THRESHOLD_DEG" \
    --max-lag "$MAX_LAG" \
    "${filter_args[@]}"

echo "Trajectory metric extraction completed."
