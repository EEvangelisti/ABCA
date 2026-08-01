#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$ROOT/utils.sh"

initialize_environment "$ROOT" "extract_local_parameters.py" "$@"

# ------------------------------------------------------------------------------

# Sanity checks
require_variables PYTHON PYTHON_SCRIPT METRICS_DIR
check_metrics_directory "$METRICS_DIR"

# Directory used to store exported local behavioural parameters.
LOCAL_PARAMETERS_DIR="${LOCAL_PARAMETERS_DIR:-$METRICS_DIR/abca_rationale}"

# Optional speed threshold used to define FAST and SLOW states.
FAST_SLOW_THRESHOLD="${FAST_SLOW_THRESHOLD:-}"

# Half-width of the hysteresis band used for state assignment.
HYSTERESIS_HALF_WIDTH="${HYSTERESIS_HALF_WIDTH:-25}"
require_integer HYSTERESIS_HALF_WIDTH non-negative

# Maximum lag used for temporal autocorrelation analyses.
MAX_LAG_STEPS="${MAX_LAG_STEPS:-25}"
require_integer MAX_LAG_STEPS positive

# Number of points used to sample empirical quantile functions.
QUANTILE_GRID_SIZE="${QUANTILE_GRID_SIZE:-1001}"
require_integer QUANTILE_GRID_SIZE ">=" 2

# Multiplier applied to cap extreme acceleration values.
ACCEL_CAP_MULTIPLIER="${ACCEL_CAP_MULTIPLIER:-3}"
require_number ACCEL_CAP_MULTIPLIER positive

# Spatial scale used by the ABCA model (µm per cell).
MICRONS_PER_CELL="${MICRONS_PER_CELL:-10}"
require_number MICRONS_PER_CELL positive

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
    require_number FAST_SLOW_THRESHOLD positive
    args+=(
        --threshold "$FAST_SLOW_THRESHOLD"
    )
fi

mkdir -p "$LOCAL_PARAMETERS_DIR"

cat <<EOF
Extracting empirical local parameters
=====================================
Metrics:                  $METRICS_DIR
Output:                   $LOCAL_PARAMETERS_DIR
FAST/SLOW threshold:      ${FAST_SLOW_THRESHOLD:-automatically inferred}
Hysteresis half-width:    $HYSTERESIS_HALF_WIDTH
Maximum lag:              $MAX_LAG_STEPS steps
Quantile grid size:       $QUANTILE_GRID_SIZE
Acceleration multiplier:  $ACCEL_CAP_MULTIPLIER
Microns per cell:         $MICRONS_PER_CELL

EOF

"$PYTHON" "$PYTHON_SCRIPT" "${args[@]}"

job_done "Local-parameter extraction completed"
