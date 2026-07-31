#!/usr/bin/env bash
#
# Analyse trajectory metrics and generate summary figures.
#
# Usage:
#   ./analyse_trajectory_metrics.sh CONFIG_FILE
#
# The Python environment is activated by run.sh. Analysis parameters are read from CONFIG_FILE.
#

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ABCA_CONFIG_DIR"

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<EOF
Usage:
  $(basename "$0") CONFIG_FILE

CONFIG_FILE is a trusted Bash configuration file containing the input/output
paths and analysis parameters.
EOF
}

if (( $# != 1 )); then
    usage >&2
    exit 1
fi

case "$1" in
    -h|--help)
        usage
        exit 0
        ;;
esac

ANALYSIS_CONFIG="$1"
PYTHON_SCRIPT="$ROOT/analyse_trajectory_metrics.py"

[[ -f "$ANALYSIS_CONFIG" ]] \
    || die "Analysis configuration file not found: $ANALYSIS_CONFIG"

[[ -f "$PYTHON_SCRIPT" ]] \
    || die "Python script not found: $PYTHON_SCRIPT"

# shellcheck disable=SC1090
source "$ANALYSIS_CONFIG"

: "${METRICS_DIR:?METRICS_DIR is not defined in $ANALYSIS_CONFIG}"

[[ -d "$METRICS_DIR" ]] \
    || die "Metrics directory not found: $METRICS_DIR"

OUTPUT_DIR="${GROUPED_ANALYSIS_DIR:-$METRICS_DIR/grouped_analysis}"
DPI="${DPI:-300}"
STATE_SPEED_THRESHOLD="${STATE_SPEED_THRESHOLD:-}"
BINS="${BINS:-50}"
COUPLING_BINS="${COUPLING_BINS:-20}"
SMOOTH_FRAC="${SMOOTH_FRAC:-0.20}"

mkdir -p "$OUTPUT_DIR"

args=(
    "$METRICS_DIR"
    --outdir "$OUTPUT_DIR"
    --dpi "$DPI"
    --bins "$BINS"
    --coupling-bins "$COUPLING_BINS"
    --smooth-frac "$SMOOTH_FRAC"
)

if [[ -n "$STATE_SPEED_THRESHOLD" ]]; then
    args+=(
        --state-speed-threshold "$STATE_SPEED_THRESHOLD"
    )
fi

echo "Analysing trajectory metrics..."
echo "  Metrics: $METRICS_DIR"
echo "  Output:  $OUTPUT_DIR"
echo "  Python:  $(command -v python)"

python "$PYTHON_SCRIPT" "${args[@]}"

echo "Trajectory analysis completed."
