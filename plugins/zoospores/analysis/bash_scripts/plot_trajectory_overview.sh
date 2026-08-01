#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$ROOT/utils.sh"

initialize_environment "$ROOT" "plot_trajectory_overview.py" "$@"

# ------------------------------------------------------------------------------

require_variables PYTHON PYTHON_SCRIPT
FILTERED_METRICS_DIR="${FILTERED_METRICS_DIR:-}"
COMPLETE_METRICS_DIR="${COMPLETE_METRICS_DIR:-}"

[[ -n "$FILTERED_METRICS_DIR" || -n "$COMPLETE_METRICS_DIR" ]] || \
    die "At least one of FILTERED_METRICS_DIR or COMPLETE_METRICS_DIR must be defined in $ANALYSIS_CONFIG"

if [[ -n "$FILTERED_METRICS_DIR" ]]; then
    check_metrics_directory "$FILTERED_METRICS_DIR"
fi

if [[ -n "$COMPLETE_METRICS_DIR" ]]; then
    check_metrics_directory "$COMPLETE_METRICS_DIR"
fi

# The Python script requires one primary metrics directory. Prefer the filtered
# dataset when available; otherwise use the complete dataset.
if [[ -n "$FILTERED_METRICS_DIR" ]]; then
    PRIMARY_METRICS_DIR="$FILTERED_METRICS_DIR"
else
    PRIMARY_METRICS_DIR="$COMPLETE_METRICS_DIR"
fi

OVERVIEW_DIR="${OVERVIEW_DIR:-$PRIMARY_METRICS_DIR/trajectory_overview}"

# Number of angular bins used for direction-distribution plots.
ANGULAR_BINS="${ANGULAR_BINS:-36}"
require_integer ANGULAR_BINS ">=" 2

# Maximum number of trajectories included in overview plots.
MAX_TRACKS="${MAX_TRACKS:-2000}"
require_integer MAX_TRACKS non-negative

# Line width used when plotting individual trajectories.
LINE_WIDTH="${LINE_WIDTH:-0.55}"
require_number LINE_WIDTH positive

# Maximum number of trajectories displayed per length decile.
MAX_TRACKS_PER_DECILE="${MAX_TRACKS_PER_DECILE:-500}"
require_integer MAX_TRACKS_PER_DECILE non-negative

# Resolution of the exported figures in dots per inch.
DPI="${DPI:-300}"
require_integer DPI positive

args=(
    "$PRIMARY_METRICS_DIR"
    --outdir "$OVERVIEW_DIR"
    --angular-bins "$ANGULAR_BINS"
    --max-tracks "$MAX_TRACKS"
    --line-width "$LINE_WIDTH"
    --max-tracks-per-decile "$MAX_TRACKS_PER_DECILE"
    --dpi "$DPI"
)

# When both datasets are supplied, the filtered dataset is used for the main
# overview plots and the complete dataset adds the unfiltered trajectory-length
# distribution.
if [[ -n "$FILTERED_METRICS_DIR" && -n "$COMPLETE_METRICS_DIR" ]]; then
    args+=(
        --complete-metrics-dir "$COMPLETE_METRICS_DIR"
    )
fi

mkdir -p "$OVERVIEW_DIR"

cat <<EOF
Generating trajectory overview
==============================
Filtered metrics: ${FILTERED_METRICS_DIR:-not specified}
Complete metrics: ${COMPLETE_METRICS_DIR:-not specified}
Primary metrics:  $PRIMARY_METRICS_DIR
Output:           $OVERVIEW_DIR

EOF

"$PYTHON" "$PYTHON_SCRIPT" "${args[@]}"

job_done "Trajectory overview completed"
