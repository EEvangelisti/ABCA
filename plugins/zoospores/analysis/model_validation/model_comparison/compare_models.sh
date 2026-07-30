#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

SETUP_CONFIG="${1:-$SCRIPT_DIR/../../setup/python.conf}"
MODULE_CONFIG="${2:-$SCRIPT_DIR/compare_models.conf}"
PYTHON_SCRIPT="$SCRIPT_DIR/compare_zoospore_models_indexed.py"

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

require_file() {
    [[ -f "$1" ]] || die "File not found: $1"
}

require_directory() {
    [[ -d "$1" ]] || die "Directory not found: $1"
}

require_variable() {
    local name="$1"
    [[ -n "${!name:-}" ]] || die "Required configuration variable is empty or undefined: $name"
}

require_integer() {
    local name="$1"
    local value="${!name:-}"
    [[ "$value" =~ ^[0-9]+$ ]] || die "$name must be a non-negative integer (received: $value)"
}

require_number() {
    local name="$1"
    local value="${!name:-}"
    [[ "$value" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "$name must be a non-negative number (received: $value)"
}

resolve_path() {
    local value="$1"
    if [[ "$value" = /* ]]; then
        printf '%s\n' "$value"
    else
        printf '%s\n' "$SCRIPT_DIR/$value"
    fi
}

require_file "$SETUP_CONFIG"
require_file "$MODULE_CONFIG"
require_file "$PYTHON_SCRIPT"

# shellcheck disable=SC1090
source "$SETUP_CONFIG"

# shellcheck disable=SC1090
source "$MODULE_CONFIG"

require_variable PYTHON
require_file "$PYTHON"

required_variables=(
    EXPERIMENTAL_ANALYSIS_DIR
    EMPIRICAL_ANALYSIS_TEMPLATE
    HMM_ANALYSIS_TEMPLATE
    DISPLACEMENT_RELATIVE_PATH
    MSD_RELATIVE_PATH
    DISPLACEMENT_COLUMN
    LAG_COLUMN
    MSD_COLUMN
    SIMULATION_FROM
    SIMULATION_TO
    CI_LEVEL
    OUTPUT_DIR
    OUTPUT_PREFIX
    LOG_FILENAME
)

for variable in "${required_variables[@]}"; do
    require_variable "$variable"
done

require_integer SIMULATION_FROM
require_integer SIMULATION_TO
require_number CI_LEVEL

(( SIMULATION_FROM >= 1 )) ||
    die "SIMULATION_FROM must be at least 1."
(( SIMULATION_TO >= SIMULATION_FROM )) ||
    die "SIMULATION_TO must be greater than or equal to SIMULATION_FROM."

EXPERIMENTAL_ANALYSIS_DIR="$(resolve_path "$EXPERIMENTAL_ANALYSIS_DIR")"
EMPIRICAL_ANALYSIS_TEMPLATE="$(resolve_path "$EMPIRICAL_ANALYSIS_TEMPLATE")"
HMM_ANALYSIS_TEMPLATE="$(resolve_path "$HMM_ANALYSIS_TEMPLATE")"
OUTPUT_DIR="$(resolve_path "$OUTPUT_DIR")"

require_directory "$EXPERIMENTAL_ANALYSIS_DIR"

EXPERIMENTAL_DISPLACEMENT="$EXPERIMENTAL_ANALYSIS_DIR/$DISPLACEMENT_RELATIVE_PATH"
EXPERIMENTAL_MSD="$EXPERIMENTAL_ANALYSIS_DIR/$MSD_RELATIVE_PATH"

require_file "$EXPERIMENTAL_DISPLACEMENT"
require_file "$EXPERIMENTAL_MSD"

DISPLACEMENT_FILENAME="$(basename -- "$DISPLACEMENT_RELATIVE_PATH")"
MSD_FILENAME="$(basename -- "$MSD_RELATIVE_PATH")"

EMPIRICAL_DISPLACEMENT="$EMPIRICAL_ANALYSIS_TEMPLATE/$(dirname -- "$DISPLACEMENT_RELATIVE_PATH")"
HMM_DISPLACEMENT="$HMM_ANALYSIS_TEMPLATE/$(dirname -- "$DISPLACEMENT_RELATIVE_PATH")"
EMPIRICAL_MSD="$EMPIRICAL_ANALYSIS_TEMPLATE/$(dirname -- "$MSD_RELATIVE_PATH")"
HMM_MSD="$HMM_ANALYSIS_TEMPLATE/$(dirname -- "$MSD_RELATIVE_PATH")"

mkdir -p "$OUTPUT_DIR"

OUTPUT_PATH_PREFIX="$OUTPUT_DIR/$OUTPUT_PREFIX"
LOG_PATH="$OUTPUT_DIR/$LOG_FILENAME"

command=(
    "$PYTHON" "$PYTHON_SCRIPT"
    --experimental-displacement "$EXPERIMENTAL_DISPLACEMENT"
    --empirical-displacement "$EMPIRICAL_DISPLACEMENT"
    --hmm-displacement "$HMM_DISPLACEMENT"
    --displacement-filename "$DISPLACEMENT_FILENAME"
    --displacement-column "$DISPLACEMENT_COLUMN"
    --experimental-msd "$EXPERIMENTAL_MSD"
    --empirical-msd "$EMPIRICAL_MSD"
    --hmm-msd "$HMM_MSD"
    --msd-filename "$MSD_FILENAME"
    --lag-column "$LAG_COLUMN"
    --msd-column "$MSD_COLUMN"
    --simulation-id-column "${SIMULATION_ID_COLUMN:-simulation_id}"
    --delimiter "${DELIMITER:-,}"
    --from "$SIMULATION_FROM"
    --to "$SIMULATION_TO"
    --ci "$CI_LEVEL"
    --output-prefix "$OUTPUT_PATH_PREFIX"
)

if [[ "${ALLOW_MISSING_SIMULATIONS:-false}" == "true" ]]; then
    command+=(--allow-missing-simulations)
fi

cat <<EOF
Model comparison
================
Python interpreter:        $PYTHON
Experimental analysis:     $EXPERIMENTAL_ANALYSIS_DIR
Empirical simulations:     $EMPIRICAL_ANALYSIS_TEMPLATE
HMM simulations:           $HMM_ANALYSIS_TEMPLATE
Simulation range:          $SIMULATION_FROM–$SIMULATION_TO
Confidence interval:       $CI_LEVEL%
Output prefix:             $OUTPUT_PATH_PREFIX
Log file:                  $LOG_PATH
EOF

"${command[@]}" 2>&1 | tee "$LOG_PATH"
