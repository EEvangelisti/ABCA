#!/usr/bin/env bash
set -Eeuo pipefail

cd ../../..

dune clean
dune build

ABCA="$(dune exec -- which abca 2>/dev/null)"

if [[ ! -x "$ABCA" ]]; then
    printf 'Error: failed to locate the ABCA executable.\n' >&2
    exit 1
fi

printf 'Using ABCA executable: %s\n' "$ABCA"

ROOT="plugins/zoospores"
MODEL="zoospores-empirical-beads"

# Experimental bead-map simulation outputs.
OUTPUT_ROOT="$ROOT/examples/experimental_bead_map_collision_rules"

# Physical field of view converted at 10 µm per ABCA cell.
ROWS=139
COLS=185

GENERATIONS=200
AGENTS=1246
MICRONS_PER_CELL=10

REPLICATES=100
MAX_JOBS="${MAX_JOBS:-10}"

PARAMS="$ROOT/empirical/data/P_nicotianae_local_parameters.csv"
QUANTILES="$ROOT/empirical/data/P_nicotianae_empirical_quantiles.csv"
BEAD_MAP="$ROOT/examples/bead_map.csv"

BEAD_RADIUS=0.5
ZOOSPORE_RADIUS=0.5
BEAD_MIN_GAP=0.0

# Shared parameters used by rules that require them.
COLLISION_SLOWDOWN=0.2
COLLISION_SPEED_FACTOR=0.05
COLLISION_RECOVERY_RATE=0.05
COLLISION_ANGULAR_SD_DEG=45

# Directory label : ordered collision-rule specification.
MODES=(
    "stop_at_contact:STOP_AT_CONTACT"
    "tangent:TANGENT"
    "slowdown:SLOWDOWN"
    "redirect:REDIRECT"
    "tangent_slowdown:TANGENT+SLOWDOWN"
    "redirect_slowdown:REDIRECT+SLOWDOWN"
)

[[ -f "$PARAMS" ]] || {
    printf 'Error: parameter file not found: %s\n' "$PARAMS" >&2
    exit 1
}

[[ -f "$QUANTILES" ]] || {
    printf 'Error: quantile file not found: %s\n' "$QUANTILES" >&2
    exit 1
}

[[ -f "$BEAD_MAP" ]] || {
    printf 'Error: bead map not found: %s\n' "$BEAD_MAP" >&2
    exit 1
}

[[ "$MAX_JOBS" =~ ^[1-9][0-9]*$ ]] || {
    printf 'Error: MAX_JOBS must be a positive integer.\n' >&2
    exit 1
}

mkdir -p "$OUTPUT_ROOT"

cleanup() {
    local status=$?

    if (( status != 0 )); then
        printf '\nError: stopping remaining simulations.\n' >&2
    fi

    jobs -pr | xargs -r kill 2>/dev/null || true
    wait 2>/dev/null || true

    exit "$status"
}

trap cleanup EXIT INT TERM

run_simulation() {
    local mode_name="$1"
    local collision_rules="$2"
    local mode_index="$3"
    local rep="$4"

    local rep_label
    local mode_dir
    local tracks_dir
    local output_prefix
    local seed

    rep_label="$(printf '%03d' "$rep")"
    mode_dir="$OUTPUT_ROOT/$mode_name"
    tracks_dir="$mode_dir/tracks_${rep_label}"
    output_prefix="$tracks_dir/P_nicotianae_empirical_beads"

    # Unique, reproducible seed for every mode × replicate pair.
    seed=$((mode_index * 100000 + rep))

    mkdir -p "$tracks_dir"

    printf '[mode=%s | rules=%s | replicate=%s | seed=%s] started\n' \
        "$mode_name" \
        "$collision_rules" \
        "$rep_label" \
        "$seed"

    "$ABCA" \
        --mode run \
        --model "$MODEL" \
        --rows "$ROWS" \
        --cols "$COLS" \
        --generations "$GENERATIONS" \
        --agents "$AGENTS" \
        --seed "$seed" \
        --plugin-arg INIT=FULL \
        --plugin-arg PARAMS="$PARAMS" \
        --plugin-arg QUANTILES="$QUANTILES" \
        --plugin-arg MICRONS_PER_CELL="$MICRONS_PER_CELL" \
        --plugin-arg BEADS=FILE \
        --plugin-arg BEAD_MAP="$BEAD_MAP" \
        --plugin-arg BEAD_RADIUS="$BEAD_RADIUS" \
        --plugin-arg ZOOSPORE_RADIUS="$ZOOSPORE_RADIUS" \
        --plugin-arg BEAD_MIN_GAP="$BEAD_MIN_GAP" \
        --plugin-arg COLLISION_RULES="$collision_rules" \
        --plugin-arg COLLISION_SLOWDOWN="$COLLISION_SLOWDOWN" \
        --plugin-arg COLLISION_SPEED_FACTOR="$COLLISION_SPEED_FACTOR" \
        --plugin-arg COLLISION_RECOVERY_RATE="$COLLISION_RECOVERY_RATE" \
        --plugin-arg COLLISION_ANGULAR_SD_DEG="$COLLISION_ANGULAR_SD_DEG" \
        --out "${output_prefix}.bin"

    "$ABCA" \
        --mode xml \
        --model "$MODEL" \
        --input "${output_prefix}.bin" \
        --xml "${output_prefix}.xml"

    printf '[mode=%s | replicate=%s | seed=%s] completed\n' \
        "$mode_name" \
        "$rep_label" \
        "$seed"
}

cat <<EOF
Experimental bead-map collision-rule simulations
================================================
Grid:                  ${ROWS} × ${COLS}
Microns per cell:      $MICRONS_PER_CELL
Agents:                $AGENTS
Generations:           $GENERATIONS
Bead map:              $BEAD_MAP
Bead radius:           $BEAD_RADIUS cells
Zoospore radius:       $ZOOSPORE_RADIUS cells
Replicates per mode:   $REPLICATES
Collision modes:       ${#MODES[@]}
Total simulations:     $((REPLICATES * ${#MODES[@]}))
Maximum parallel jobs: $MAX_JOBS
Output:                $OUTPUT_ROOT

EOF

mode_index=0

for mode_definition in "${MODES[@]}"; do
    ((mode_index += 1))

    mode_name="${mode_definition%%:*}"
    collision_rules="${mode_definition#*:}"
    mode_dir="$OUTPUT_ROOT/$mode_name"

    mkdir -p "$mode_dir"

    printf '\nMode %d/%d: %s (%s)\n' \
        "$mode_index" \
        "${#MODES[@]}" \
        "$mode_name" \
        "$collision_rules"

    for ((rep = 1; rep <= REPLICATES; rep++)); do
        run_simulation \
            "$mode_name" \
            "$collision_rules" \
            "$mode_index" \
            "$rep" &

        while (( $(jobs -rp | wc -l) >= MAX_JOBS )); do
            wait -n
        done
    done
done

wait

trap - EXIT INT TERM

printf '\nAll collision-rule simulations completed successfully.\n'
