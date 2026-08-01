#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$ROOT/utils.sh"

initialize_environment "$ROOT" "validate_simulations.py" "$@"

# ------------------------------------------------------------------------------

require_variables \
    PYTHON \
    PYTHON_SCRIPT \
    EXPERIMENTAL_DIR \
    SIMULATIONS_ROOT \
    OUTPUT_DIR \
    SIMULATION_PATTERN

require_directory "$EXPERIMENTAL_DIR" "Experimental analysis directory"
require_directory "$SIMULATIONS_ROOT" "Simulations root directory"

# Resolution of the exported figures in dots per inch.
DPI="${DPI:-300}"
require_integer DPI positive

# Number of bins used for histogram-based comparisons.
BINS="${BINS:-50}"
require_integer BINS ">=" 2

args=(
    "$EXPERIMENTAL_DIR"
    "$SIMULATIONS_ROOT"
    --outdir "$OUTPUT_DIR"
    --simulation-pattern "$SIMULATION_PATTERN"
    --bins "$BINS"
    --dpi "$DPI"
)

if [[ -n "${UPPER_PERCENTILE:-}" ]]; then
    require_number UPPER_PERCENTILE ">" 0 "<=" 100
    args+=(--upper-percentile "$UPPER_PERCENTILE")
fi

mkdir -p "$OUTPUT_DIR"

cat <<EOF
Simulation validation
=====================
Experimental data:   $EXPERIMENTAL_DIR
Simulations root:    $SIMULATIONS_ROOT
Simulation pattern:  $SIMULATION_PATTERN
Output directory:    $OUTPUT_DIR
Histogram bins:      $BINS
Upper percentile:    ${UPPER_PERCENTILE:-none}
Figure resolution:   $DPI dpi

EOF

"$PYTHON" "$PYTHON_SCRIPT" "${args[@]}"

job_done "Simulation validation completed"
