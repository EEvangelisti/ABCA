#!/usr/bin/env bash
set -euo pipefail

# Run from plugins/zoospores_AI/examples/
cd ../../..

dune clean
dune build
ABCA="$(dune exec which abca 2>/dev/null)"

if [[ ! -x "$ABCA" ]]; then
    echo "Error: failed to locate the ABCA executable." >&2
    exit 1
fi

echo "Using ABCA executable: $ABCA"

ROOT="plugins/zoospores_AI"
DATA="$ROOT/canonical_fit"
PARAMS="$DATA/canonical_parameters.toml"
OUTDIR="$ROOT/examples"

MODEL="${1:?Usage: $0 MODEL N_RUNS [MAX_JOBS]}"
N_RUNS="${2:?Usage: $0 MODEL N_RUNS [MAX_JOBS]}"
MAX_JOBS="${3:-5}"

mkdir -p "$OUTDIR"

# Shell-friendly model name for output files.
MODEL_TAG="$(printf '%s' "$MODEL" | tr '[:upper:]' '[:lower:]')"

echo "Canonical model : $MODEL"
echo "Parameter file  : $PARAMS"
echo "Runs            : $N_RUNS"
echo "Max jobs        : $MAX_JOBS"
echo "Agents/run      : 2000"

for SEED in $(seq 1 "$N_RUNS"); do
    BASE="P_nicotianae_${MODEL_TAG}_$(printf '%06d' "$SEED")"
    BIN="$OUTDIR/$BASE.bin"
    XML="$OUTDIR/$BASE.xml"

    (
        echo "[$SEED/$N_RUNS] Running $MODEL..."

        OCAMLRUNPARAM=b "$ABCA" \
            --mode run \
            --model "$MODEL" \
            --rows 800 \
            --cols 800 \
            --generations 100 \
            --agents 2000 \
            --seed "$SEED" \
            --plugin-arg INIT=DISK \
            --plugin-arg RADIUS=100 \
            --plugin-arg PARAMETER_FILE="$PARAMS" \
            --out "$BIN"

        echo "[$SEED/$N_RUNS] Exporting trajectories to XML..."

        "$ABCA" \
            --mode xml \
            --model "$MODEL" \
            --input "$BIN" \
            --xml "$XML"

        echo "[$SEED/$N_RUNS] Done."
    ) &

    # Do not exceed the maximum number of parallel jobs.
    while (( $(jobs -rp | wc -l) >= MAX_JOBS )); do
        wait -n
    done
done

# Wait for the remaining jobs to finish.
wait

echo "All runs completed for $MODEL."
