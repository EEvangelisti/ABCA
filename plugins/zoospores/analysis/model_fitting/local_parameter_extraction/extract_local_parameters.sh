#!/usr/bin/env bash
#
# Extract empirical local parameters for the zoospore ABCA model.
#
# Usage:
#   ./extract_local_parameters.sh CONFIG_FILE
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
paths and local-parameter extraction settings.
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
PYTHON_SCRIPT="$ROOT/extract_local_parameters.py"

[[ -f "$ANALYSIS_CONFIG" ]] \
    || die "Analysis configuration file not found: $ANALYSIS_CONFIG"

[[ -f "$PYTHON_SCRIPT" ]] \
    || die "Python script not found: $PYTHON_SCRIPT"

# shellcheck disable=SC1090
source "$ANALYSIS_CONFIG"

: "${METRICS_DIR:?METRICS_DIR is not defined in $ANALYSIS_CONFIG}"

[[ -d "$METRICS_DIR" ]] \
    || die "Metrics directory not found: $METRICS_DIR"

[[ -f "$METRICS_DIR/step_metrics.csv" ]] \
    || die "Required file not found: $METRICS_DIR/step_metrics.csv"

[[ -f "$METRICS_DIR/track_metrics.csv" ]] \
    || die "Required file not found: $METRICS_DIR/track_metrics.csv"

LOCAL_PARAMETERS_DIR="${LOCAL_PARAMETERS_DIR:-$METRICS_DIR/abca_rationale}"

FAST_SLOW_THRESHOLD="${FAST_SLOW_THRESHOLD:-}"
HYSTERESIS_HALF_WIDTH="${HYSTERESIS_HALF_WIDTH:-25}"
MAX_LAG_STEPS="${MAX_LAG_STEPS:-25}"
QUANTILE_GRID_SIZE="${QUANTILE_GRID_SIZE:-1001}"
ACCEL_CAP_MULTIPLIER="${ACCEL_CAP_MULTIPLIER:-3}"
MICRONS_PER_CELL="${MICRONS_PER_CELL:-10}"

mkdir -p "$LOCAL_PARAMETERS_DIR"

args=(
    "$METRICS_DIR"
    --outdir "$LOCAL_PARAMETERS_DIR"
    --hysteresis-half-width "$HYSTERESIS_HALF_WIDTH"
    --max-lag-steps "$MAX_LAG_STEPS"
    --quantile-grid-size "$QUANTILE_GRID_SIZE"
    --accel-cap-multiplier "$ACCEL_CAP_MULTIPLIER"
    --microns-per-cell "$MICRONS_PER_CELL"
)

# When no explicit threshold is supplied, the Python script estimates one
# automatically from the speed distribution.
if [[ -n "$FAST_SLOW_THRESHOLD" ]]; then
    args+=(
        --threshold "$FAST_SLOW_THRESHOLD"
    )
fi

echo "Extracting empirical local parameters..."
echo "  Metrics:                  $METRICS_DIR"
echo "  Output:                   $LOCAL_PARAMETERS_DIR"
echo "  FAST/SLOW threshold:      ${FAST_SLOW_THRESHOLD:-automatically inferred}"
echo "  Hysteresis half-width:    $HYSTERESIS_HALF_WIDTH"
echo "  Maximum lag:              $MAX_LAG_STEPS steps"
echo "  Quantile grid size:       $QUANTILE_GRID_SIZE"
echo "  Acceleration multiplier:  $ACCEL_CAP_MULTIPLIER"
echo "  Microns per cell:         $MICRONS_PER_CELL"
echo "  Python:                   $(command -v python)"

python "$PYTHON_SCRIPT" "${args[@]}"

echo "Local-parameter extraction completed."
