#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$ROOT/utils.sh"

initialize_environment "$ROOT" "resample_trajectories.py" "$@"

# ------------------------------------------------------------------------------

require_variables \
    PYTHON \
    PYTHON_SCRIPT \
    INPUT_DIR \
    OUTPUT_DIR \
    EMPIRICAL_LENGTHS \
    INITIAL_SEED

require_directory "$INPUT_DIR" "Simulated TrackMate XML directory"
require_file "$EMPIRICAL_LENGTHS" "Empirical lengths file"

# Maximum number of parallel jobs; defaults to one quarter of available CPUs.
CPU_COUNT="$(nproc)"
MAX_JOBS="${MAX_JOBS:-$(( CPU_COUNT / 4 ))}"
(( MAX_JOBS >= 1 )) || MAX_JOBS=1

require_integer MAX_JOBS positive

(( MAX_JOBS <= CPU_COUNT )) \
    || die "MAX_JOBS must not exceed the number of available CPUs ($CPU_COUNT)."

# Initial random seed assigned to the first resampling job.
require_integer INITIAL_SEED non-negative

shopt -s nullglob
xml_files=("$INPUT_DIR"/*.xml)
shopt -u nullglob

(( ${#xml_files[@]} > 0 )) \
    || die "No XML files found in $INPUT_DIR"

mkdir -p "$OUTPUT_DIR"

cat <<EOF
Trajectory resampling
=====================
Input directory:       $INPUT_DIR
Output directory:      $OUTPUT_DIR
Empirical lengths:     $EMPIRICAL_LENGTHS
XML files:             ${#xml_files[@]}
Available CPUs:        $CPU_COUNT
Maximum parallel jobs: $MAX_JOBS
Initial random seed:   $INITIAL_SEED

EOF

seed="$INITIAL_SEED"
total="${#xml_files[@]}"
index=0

for xml in "${xml_files[@]}"; do
    wait_for_job_slot "$MAX_JOBS"

    ((index += 1))

    base="$(basename -- "$xml")"
    output_xml="$OUTPUT_DIR/$base"
    job_seed="$seed"
    job_index="$index"

    args=(
        "$xml"
        "$EMPIRICAL_LENGTHS"
        "$output_xml"
        --seed "$job_seed"
    )

    (
        printf '[%d/%d] Resampling %s (seed=%d)...\n' \
            "$job_index" "$total" "$base" "$job_seed"

        "$PYTHON" "$PYTHON_SCRIPT" "${args[@]}"

        printf '[%d/%d] Completed %s.\n' \
            "$job_index" "$total" "$base"
    ) &

    ((seed += 1))
done

wait

job_done "All resampling jobs completed"
