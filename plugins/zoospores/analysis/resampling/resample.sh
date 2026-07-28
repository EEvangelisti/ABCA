#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
source resample.conf

MAX_JOBS="${1:-5}"
INITIAL_SEED="${2:-1}"

if ! [[ "$MAX_JOBS" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: MAX_JOBS must be a positive integer." >&2
    exit 2
fi

if ! [[ "$INITIAL_SEED" =~ ^[0-9]+$ ]]; then
    echo "Error: INITIAL_SEED must be a non-negative integer." >&2
    exit 2
fi

for required_file in "$PYTHON" "resample.py" "$EMPIRICAL_LENGTHS"; do
    if [[ ! -f "$required_file" ]]; then
        echo "Error: required file not found: $required_file" >&2
        exit 1
    fi
done

if [[ ! -x "$PYTHON" ]]; then
    echo "Error: Python interpreter is not executable: $PYTHON" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

shopt -s nullglob
xml_files=("$INPUT_DIR"/*.xml)
shopt -u nullglob

if (( ${#xml_files[@]} == 0 )); then
    echo "Error: no XML files found in $INPUT_DIR" >&2
    exit 1
fi

seed="$INITIAL_SEED"
total="${#xml_files[@]}"
index=0

for xml in "${xml_files[@]}"; do
    ((index += 1))
    base="$(basename -- "$xml")"
    output_xml="$OUTPUT_DIR/$base"

    (
        echo "[$index/$total] Resampling $base (seed=$seed)..."

        "$PYTHON" resample.py \
            "$xml" \
            "$EMPIRICAL_LENGTHS" \
            "$output_xml" \
            --seed "$seed"

        echo "[$index/$total] Completed $base."
    ) &

    ((seed += 1))

    while (( $(jobs -rp | wc -l) >= MAX_JOBS )); do
        wait -n
    done
done

wait

echo "All resampling jobs completed."
