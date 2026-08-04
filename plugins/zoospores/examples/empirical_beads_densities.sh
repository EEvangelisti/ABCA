#!/usr/bin/env bash
set -Eeuo pipefail

cd ../../..

dune clean
dune build

ABCA="$(dune exec -- which abca 2>/dev/null)"

if [[ ! -x "$ABCA" ]]; then
    echo "Error: failed to locate the ABCA executable." >&2
    exit 1
fi

echo "Using ABCA executable: $ABCA"

ROOT="plugins/zoospores"
MODEL="zoospores-empirical-beads"
OUTPUT_ROOT="$ROOT/examples/random_bead_density"

ROWS=400
COLS=400
GENERATIONS=200
AGENTS=2000

REPLICATES=100
MAX_JOBS="${MAX_JOBS:-10}"

BEAD_RADIUS=0.5
ZOOSPORE_RADIUS=0.5
BEAD_MIN_GAP=0.0

# Fractions of the simulated surface theoretically occupied by beads:
# 0.01 = 1 %, 0.10 = 10 %, etc.
DENSITIES=(
    0.00
    0.01
    0.02
    0.05
    0.10
    0.15
)

mkdir -p "$OUTPUT_ROOT"

# Kill remaining background jobs if the script is interrupted or fails.
cleanup() {
    local status=$?

    if (( status != 0 )); then
        echo
        echo "Error: stopping remaining simulations." >&2
    fi

    jobs -pr | xargs -r kill 2>/dev/null || true
    wait 2>/dev/null || true

    exit "$status"
}

trap cleanup EXIT INT TERM

run_simulation() {
    local density="$1"
    local bead_count="$2"
    local density_index="$3"
    local rep="$4"

    local rep_label
    local density_label
    local density_dir
    local rep_dir
    local output_prefix
    local seed

    rep_label="$(printf "%03d" "$rep")"
    density_label="${density//./p}"

    density_dir="$OUTPUT_ROOT/density_${density_label}"
    rep_dir="$density_dir/rep_${rep_label}"
    output_prefix="$rep_dir/P_nicotianae_empirical_beads"

    # Unique and reproducible seed for every density × replicate pair.
    seed=$((density_index * 100000 + rep))

    mkdir -p "$rep_dir"

    echo "[density=$density | replicate=$rep_label | seed=$seed] started"

    "$ABCA" \
        --mode run \
        --model "$MODEL" \
        --rows "$ROWS" \
        --cols "$COLS" \
        --generations "$GENERATIONS" \
        --agents "$AGENTS" \
        --seed "$seed" \
        --plugin-arg INIT=FULL \
        --plugin-arg PARAMS="$ROOT/empirical/data/P_nicotianae_local_parameters.csv" \
        --plugin-arg QUANTILES="$ROOT/empirical/data/P_nicotianae_empirical_quantiles.csv" \
        --plugin-arg MICRONS_PER_CELL=10 \
        --plugin-arg BEADS=RANDOM \
        --plugin-arg BEAD_COUNT="$bead_count" \
        --plugin-arg BEAD_RADIUS="$BEAD_RADIUS" \
        --plugin-arg ZOOSPORE_RADIUS="$ZOOSPORE_RADIUS" \
        --plugin-arg BEAD_MIN_GAP="$BEAD_MIN_GAP" \
        --plugin-arg COLLISION_RESPONSE=TANGENT \
        --out "${output_prefix}.bin"

    "$ABCA" \
        --mode xml \
        --model "$MODEL" \
        --input "${output_prefix}.bin" \
        --xml "${output_prefix}.xml"

    echo "[density=$density | replicate=$rep_label | seed=$seed] completed"
}

density_index=0

for density in "${DENSITIES[@]}"; do
    ((density_index += 1))

    bead_count="$(
        awk \
            -v density="$density" \
            -v rows="$ROWS" \
            -v cols="$COLS" \
            -v radius="$BEAD_RADIUS" \
            'BEGIN {
                pi = atan2(0, -1)
                count = density * rows * cols / (pi * radius * radius)
                printf "%d\n", int(count + 0.5)
            }'
    )"

    density_label="${density//./p}"
    density_dir="$OUTPUT_ROOT/density_${density_label}"
    mkdir -p "$density_dir"

    cat <<EOF

============================================================
Density:      $density
Surface:      $(awk -v d="$density" 'BEGIN { printf "%.1f %%", 100*d }')
Bead count:   $bead_count
Replicates:   $REPLICATES
Parallel jobs: $MAX_JOBS
Output:       $density_dir
============================================================
EOF

    for ((rep = 1; rep <= REPLICATES; rep++)); do
        run_simulation \
            "$density" \
            "$bead_count" \
            "$density_index" \
            "$rep" &

        # Keep at most MAX_JOBS simulations active.
        while (( $(jobs -rp | wc -l) >= MAX_JOBS )); do
            wait -n
        done
    done
done

# Wait for the final active simulations.
wait

trap - EXIT INT TERM

echo
echo "All density simulations completed successfully."
