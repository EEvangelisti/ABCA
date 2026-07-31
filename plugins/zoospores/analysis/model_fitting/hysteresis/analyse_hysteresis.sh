#!/usr/bin/env bash
#
# Analyse the sensitivity of FAST/SLOW segmentation to hysteresis width.
#
# Usage:
#   ./analyse_hysteresis.sh CONFIG_FILE
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
paths and hysteresis-analysis parameters.
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
PYTHON_SCRIPT="$ROOT/analyse_hysteresis.py"

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

HYSTERESIS_DIR="${HYSTERESIS_DIR:-$METRICS_DIR/fast_slow_hysteresis_sensitivity}"

HYSTERESIS_WIDTHS="${HYSTERESIS_WIDTHS:-0,5,10,15,20,30,40}"
OTSU_BINS="${OTSU_BINS:-256}"
HISTOGRAM_BINS="${HISTOGRAM_BINS:-50}"
DPI="${DPI:-300}"

mkdir -p "$HYSTERESIS_DIR"

args=(
    "$METRICS_DIR"
    --outdir "$HYSTERESIS_DIR"
    --hysteresis-widths "$HYSTERESIS_WIDTHS"
    --otsu-bins "$OTSU_BINS"
    --bins "$HISTOGRAM_BINS"
    --dpi "$DPI"
)

echo "Analysing FAST/SLOW hysteresis sensitivity..."
echo "  Metrics:            $METRICS_DIR"
echo "  Output:             $HYSTERESIS_DIR"
echo "  Hysteresis widths:  $HYSTERESIS_WIDTHS"
echo "  Otsu bins:          $OTSU_BINS"
echo "  Histogram bins:     $HISTOGRAM_BINS"
echo "  Python:             $(command -v python)"

python "$PYTHON_SCRIPT" "${args[@]}"

echo "Hysteresis analysis completed."
