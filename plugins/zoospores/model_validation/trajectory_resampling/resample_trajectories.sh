#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PYTHON_CONF="../../setup/python.conf"
CONFIG_FILE="${1:-resample_trajectories.conf}"
SCRIPT="resample_trajectories.py"

if [[ ! -f "$PYTHON_CONF" ]]; then
    echo "Error: Python configuration file not found: $PYTHON_CONF" >&2
    exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: configuration file not found: $CONFIG_FILE" >&2
    exit 1
fi

# Shared Python interpreter, then module-specific settings.
# shellcheck disable=SC1090
source "$PYTHON_CONF"
# shellcheck disable=SC1090
source "$CONFIG_FILE"

required_variables=(
    PYTHON
    INPUT_DIR
    OUTPUT_DIR
    EMPIRICAL_LENGTHS
    MAX_JOBS
    INITIAL_SEED
)

for variable in "${required_variables[@]}"; do
    if [[ -z "${!variable:-}" ]]; then
        echo "Error: required variable is unset or empty: $variable" >&2
        exit 1
    fi
done

if [[ ! -f "$PYTHON" ]]; then
    echo "Error: Python interpreter not found: $PYTHON" >&2
    exit 1
fi

if [[ ! -x "$PYTHON" ]]; then
    echo "Error: Python interpreter is not executable: $PYTHON" >&2
    exit 1
fi

for required_file in "$SCRIPT" "$EMPIRICAL_LENGTHS"; do
    if [[ ! -f "$required_file" ]]; then
        echo "Error: required file not found: $required_file" >&2
        exit 1
    fi
done

if [[ ! -d "$INPUT_DIR" ]]; then
    echo "Error: input directory not found: $INPUT_DIR" >&2
    exit 1
fi

if ! [[ "$MAX_JOBS" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: MAX_JOBS must be a positive integer." >&2
    exit 2
fi

if ! [[ "$INITIAL_SEED" =~ ^[0-9]+$ ]]; then
    echo "Error: INITIAL_SEED must be a non-negative integer." >&2
    exit 2
fi

mkdir -p "$OUTPUT_DIR"

shopt -s nullglob
xml_files=("$INPUT_DIR"/*.xml)
shopt -u nullglob

if (( ${#xml_files[@]} == 0 )); then
    echo "Error: no XML files found in $INPUT_DIR" >&2
    exit 1
fi

echo "Trajectory resampling"
echo "====================="
echo "Python interpreter:    $PYTHON"
echo "Configuration file:    $CONFIG_FILE"
echo "Input directory:       $INPUT_DIR"
echo "Output directory:      $OUTPUT_DIR"
echo "Empirical lengths:     $EMPIRICAL_LENGTHS"
echo "XML files:             ${#xml_files[@]}"
echo "Maximum parallel jobs: $MAX_JOBS"
echo "Initial random seed:   $INITIAL_SEED"
echo

seed="$INITIAL_SEED"
total="${#xml_files[@]}"
index=0

for xml in "${xml_files[@]}"; do
    ((index += 1))
    base="$(basename -- "$xml")"
    output_xml="$OUTPUT_DIR/$base"
    job_seed="$seed"
    job_index="$index"

    (
        echo "[$job_index/$total] Resampling $base (seed=$job_seed)..."

        "$PYTHON" "$SCRIPT" \
            "$xml" \
            "$EMPIRICAL_LENGTHS" \
            "$output_xml" \
            --seed "$job_seed"

        echo "[$job_index/$total] Completed $base."
    ) &

    ((seed += 1))

    while (( $(jobs -rp | wc -l) >= MAX_JOBS )); do
        wait -n
    done
done

wait

echo
echo "All resampling jobs completed."
