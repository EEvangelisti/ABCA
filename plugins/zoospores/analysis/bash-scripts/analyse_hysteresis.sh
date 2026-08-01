#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$ROOT/utils.sh"

initialize_environment "$ROOT" "analyse_hysteresis.py" "$@"

# ------------------------------------------------------------------------------

require_variables PYTHON PYTHON_SCRIPT METRICS_DIR
check_metrics_directory "$METRICS_DIR"

# Directory used to store hysteresis sensitivity-analysis outputs.
HYSTERESIS_DIR="${HYSTERESIS_DIR:-$METRICS_DIR/fast_slow_hysteresis_sensitivity}"

# Comma-separated hysteresis widths evaluated during sensitivity analysis.
HYSTERESIS_WIDTHS="${HYSTERESIS_WIDTHS:-0,5,10,15,20,30,40}"

# Number of histogram bins used for Otsu threshold estimation.
OTSU_BINS="${OTSU_BINS:-256}"
require_integer OTSU_BINS ">=" 2

# Number of bins used for output histograms.
HISTOGRAM_BINS="${HISTOGRAM_BINS:-50}"
require_integer HISTOGRAM_BINS ">=" 2

# Resolution of the exported figures in dots per inch.
DPI="${DPI:-300}"
require_integer DPI positive

args=(
    "$METRICS_DIR"
    --outdir "$HYSTERESIS_DIR"
    --hysteresis-widths "$HYSTERESIS_WIDTHS"
    --otsu-bins "$OTSU_BINS"
    --bins "$HISTOGRAM_BINS"
    --dpi "$DPI"
)

mkdir -p "$HYSTERESIS_DIR"

cat <<EOF
Analysing FAST/SLOW hysteresis sensitivity
==========================================
Metrics:            $METRICS_DIR
Output:             $HYSTERESIS_DIR
Hysteresis widths:  $HYSTERESIS_WIDTHS
Otsu bins:          $OTSU_BINS
Histogram bins:     $HISTOGRAM_BINS

EOF

"$PYTHON" "$PYTHON_SCRIPT" "${args[@]}"

job_done "Hysteresis analysis completed"
