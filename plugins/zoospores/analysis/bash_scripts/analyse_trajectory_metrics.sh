#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$ROOT/utils.sh"

initialize_environment "$ROOT" "analyse_trajectory_metrics.py" "$@"

# ------------------------------------------------------------------------------

require_variables PYTHON PYTHON_SCRIPT METRICS_DIR
require_directory "$METRICS_DIR" "Metrics directory"

# Directory used to store grouped-analysis outputs.
OUTPUT_DIR="${GROUPED_ANALYSIS_DIR:-$METRICS_DIR/grouped_analysis}"

# Resolution of the exported figures in dots per inch.
DPI="${DPI:-300}"
require_integer DPI positive

# Optional speed threshold used to define behavioural states.
STATE_SPEED_THRESHOLD="${STATE_SPEED_THRESHOLD:-}"

# Number of bins used for histogram-based analyses.
BINS="${BINS:-50}"
require_integer BINS ">=" 2

# Number of bins used for speed–turning coupling analysis.
COUPLING_BINS="${COUPLING_BINS:-20}"
require_integer COUPLING_BINS ">=" 2

# Fraction of data used for LOWESS smoothing.
SMOOTH_FRAC="${SMOOTH_FRAC:-0.20}"
require_number SMOOTH_FRAC ">" 0.0 "<=" 1.0

args=(
    "$METRICS_DIR"
    --outdir "$OUTPUT_DIR"
    --dpi "$DPI"
    --bins "$BINS"
    --coupling-bins "$COUPLING_BINS"
    --smooth-frac "$SMOOTH_FRAC"
)

if [[ -n "$STATE_SPEED_THRESHOLD" ]]; then
    require_number STATE_SPEED_THRESHOLD non-negative
    args+=(--state-speed-threshold "$STATE_SPEED_THRESHOLD")
fi

mkdir -p "$OUTPUT_DIR"

cat <<EOF
Analysing trajectory metrics
============================
Metrics: $METRICS_DIR
Output:  $OUTPUT_DIR

EOF

"$PYTHON" "$PYTHON_SCRIPT" "${args[@]}"

job_done "Trajectory analysis completed"
