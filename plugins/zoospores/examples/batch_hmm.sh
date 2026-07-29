#!/usr/bin/env bash
set -euo pipefail

cd ../../..

dune clean
dune build
ABCA="$(dune exec which abca 2>/dev/null)"

if [[ ! -x "$ABCA" ]]; then
    echo "Error: failed to locate the ABCA executable." >&2
    exit 1
fi

echo "Using ABCA executable: $ABCA"

ROOT="plugins/zoospores"
DATA="$ROOT/hmm/data"

N_RUNS="${1:?Usage: $0 N_RUNS [MAX_JOBS]}"
MAX_JOBS="${2:-5}"

for SEED in $(seq 1 "$N_RUNS"); do
    BASE="P_nicotianae_hmm_$(printf '%06d' "$SEED")"
    BIN="$ROOT/examples/$BASE.bin"
    XML="$ROOT/examples/$BASE.xml"

    (
        # Run the simulation.
        echo "[$SEED/$N_RUNS] Running simulation..."
        $ABCA \
            --mode run \
            --model zoospores-hmm \
            --rows 800 \
            --cols 800 \
            --generations 100 \
            --agents 2500 \
            --seed "$SEED" \
            --toroidal \
            --plugin-arg INIT=CIRCLE \
            --plugin-arg RADIUS=100 \
            --plugin-arg TRANSITIONS=$DATA/P_nicotianae_hmm_transition_matrix.tsv \
            --plugin-arg START_PROBABILITIES=$DATA/P_nicotianae_hmm_start_probabilities.tsv \
            --plugin-arg STATE_QUANTILES=$DATA/P_nicotianae_hmm_state_quantiles.tsv \
            --plugin-arg MICRONS_PER_CELL=10 \
            --out "$BIN"

        # Export trajectories to an XML file.
        echo "[$SEED/$N_RUNS] Exporting trajectories to XML..."
        $ABCA \
            --mode xml \
            --model zoospores-hmm \
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

echo "All runs completed."
