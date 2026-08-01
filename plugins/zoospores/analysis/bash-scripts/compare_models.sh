#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$ROOT/utils.sh"

initialize_environment "$ROOT" "compare_models.py" "$@"

# ------------------------------------------------------------------------------

require_variables \
  PYTHON \
  PYTHON_SCRIPT \
  EXPERIMENTAL_ANALYSIS_DIR \
  EMPIRICAL_ANALYSIS_TEMPLATE \
  HMM_ANALYSIS_TEMPLATE \
  DISPLACEMENT_RELATIVE_PATH \
  MSD_RELATIVE_PATH \
  DISPLACEMENT_COLUMN \
  LAG_COLUMN \
  MSD_COLUMN \
  SIMULATION_FROM \
  SIMULATION_TO \
  CI_LEVEL \
  OUTPUT_DIR \
  OUTPUT_PREFIX \
  LOG_FILENAME

require_directory "$EXPERIMENTAL_ANALYSIS_DIR" "Experimental analysis directory"

require_integer SIMULATION_FROM ">=" 1
require_integer SIMULATION_TO ">=" "$SIMULATION_FROM"
require_number CI_LEVEL ">" 0 "<=" 100

# Experimental reference files.
EXPERIMENTAL_DISPLACEMENT="$EXPERIMENTAL_ANALYSIS_DIR/$DISPLACEMENT_RELATIVE_PATH"
require_file "$EXPERIMENTAL_DISPLACEMENT" "Experimental displacement data"

EXPERIMENTAL_MSD="$EXPERIMENTAL_ANALYSIS_DIR/$MSD_RELATIVE_PATH"
require_file "$EXPERIMENTAL_MSD" "Experimental MSD data"

# Reference file names.
DISPLACEMENT_FILENAME="$(basename -- "$DISPLACEMENT_RELATIVE_PATH")"
MSD_FILENAME="$(basename -- "$MSD_RELATIVE_PATH")"

# Simulation output directories.
EMPIRICAL_DISPLACEMENT="$EMPIRICAL_ANALYSIS_TEMPLATE/$(dirname -- "$DISPLACEMENT_RELATIVE_PATH")"
HMM_DISPLACEMENT="$HMM_ANALYSIS_TEMPLATE/$(dirname -- "$DISPLACEMENT_RELATIVE_PATH")"
EMPIRICAL_MSD="$EMPIRICAL_ANALYSIS_TEMPLATE/$(dirname -- "$MSD_RELATIVE_PATH")"
HMM_MSD="$HMM_ANALYSIS_TEMPLATE/$(dirname -- "$MSD_RELATIVE_PATH")"

# Output file prefix.
OUTPUT_PATH_PREFIX="$OUTPUT_DIR/$OUTPUT_PREFIX"

# Log file path.
LOG_PATH="$OUTPUT_DIR/$LOG_FILENAME"

args=(
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

ALLOW_MISSING_SIMULATIONS="${ALLOW_MISSING_SIMULATIONS:-false}"
require_choice ALLOW_MISSING_SIMULATIONS 0 1 true false yes no on off

case "$ALLOW_MISSING_SIMULATIONS" in
    1|true|yes|on)
        args+=(--allow-missing-simulations)
        ;;
esac

mkdir -p "$OUTPUT_DIR"

cat <<EOF
Model comparison
================
Experimental analysis:     $EXPERIMENTAL_ANALYSIS_DIR
Empirical simulations:     $EMPIRICAL_ANALYSIS_TEMPLATE
HMM simulations:           $HMM_ANALYSIS_TEMPLATE
Simulation range:          $SIMULATION_FROM-$SIMULATION_TO
Confidence interval:       $CI_LEVEL%
Output prefix:             $OUTPUT_PATH_PREFIX
Log file:                  $LOG_PATH

EOF

"$PYTHON" "$PYTHON_SCRIPT" "${args[@]}" 2>&1 | tee "$LOG_PATH"

job_done "Model comparison completed"
