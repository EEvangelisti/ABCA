#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ABCA_CONFIG_DIR"
CONFIG_FILE="$1"
SCRIPT="$SCRIPT_DIR/validate_simulations.py"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: configuration file not found: $CONFIG_FILE" >&2
    exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

required_variables=(
    EXPERIMENTAL_DIR
    SIMULATIONS_ROOT
    OUTPUT_DIR
    SIMULATION_PATTERN
    BINS
    DPI
)

for variable in "${required_variables[@]}"; do
    if [[ -z "${!variable:-}" ]]; then
        echo "Error: required variable is unset or empty: $variable" >&2
        exit 1
    fi
done

if [[ ! -f "$SCRIPT" ]]; then
    echo "Error: validation script not found: $SCRIPT" >&2
    exit 1
fi

if [[ ! -d "$EXPERIMENTAL_DIR" ]]; then
    echo "Error: experimental analysis directory not found: $EXPERIMENTAL_DIR" >&2
    exit 1
fi

if [[ ! -d "$SIMULATIONS_ROOT" ]]; then
    echo "Error: simulations root directory not found: $SIMULATIONS_ROOT" >&2
    exit 1
fi

if ! [[ "$BINS" =~ ^[0-9]+$ ]] || (( BINS < 2 )); then
    echo "Error: BINS must be an integer greater than or equal to 2." >&2
    exit 2
fi

if ! [[ "$DPI" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: DPI must be a positive integer." >&2
    exit 2
fi

if [[ -n "${UPPER_PERCENTILE:-}" ]]; then
    if ! python - "$UPPER_PERCENTILE" <<'PY'
import sys

try:
    value = float(sys.argv[1])
except ValueError:
    raise SystemExit(1)

raise SystemExit(0 if 0.0 < value <= 100.0 else 1)
PY
    then
        echo "Error: UPPER_PERCENTILE must be numeric and in ]0, 100], or empty." >&2
        exit 2
    fi
fi

mkdir -p "$OUTPUT_DIR"

args=(
    "$EXPERIMENTAL_DIR"
    "$SIMULATIONS_ROOT"
    --outdir "$OUTPUT_DIR"
    --simulation-pattern "$SIMULATION_PATTERN"
    --bins "$BINS"
    --dpi "$DPI"
)

if [[ -n "${UPPER_PERCENTILE:-}" ]]; then
    args+=(--upper-percentile "$UPPER_PERCENTILE")
fi

echo "Simulation validation"
echo "====================="
echo "Python interpreter:  $(command -v python)"
echo "Configuration file:  $CONFIG_FILE"
echo "Experimental data:   $EXPERIMENTAL_DIR"
echo "Simulations root:    $SIMULATIONS_ROOT"
echo "Simulation pattern:  $SIMULATION_PATTERN"
echo "Output directory:    $OUTPUT_DIR"
echo "Histogram bins:      $BINS"
echo "Upper percentile:    ${UPPER_PERCENTILE:-none}"
echo "Figure resolution:   $DPI dpi"
echo

python "$SCRIPT" "${args[@]}"

echo
echo "Simulation validation completed."
