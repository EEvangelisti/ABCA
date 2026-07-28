#!/usr/bin/env bash
set -euo pipefail

cd ../../..

ROOT="plugins/zoospores"
DATA="$ROOT/empirical/data"

N_RUNS="${1:?Usage: $0 N_RUNS [MAX_JOBS]}"
MAX_JOBS="${2:-5}"

for SEED in $(seq 1 "$N_RUNS"); do
    BASE="P_nicotianae_empirical_$(printf '%06d' "$SEED")"
    BIN="$ROOT/examples/$BASE.bin"
    XML="$ROOT/examples/$BASE.xml"

    (
        # Run the simulation.
        echo "[$SEED/$N_RUNS] Running simulation..."
        dune exec abca -- \
            --mode run \
            --model zoospores-empirical \
            --rows 800 \
            --cols 800 \
            --generations 100 \
            --agents 2500 \
            --seed "$SEED" \
            --toroidal \
            --plugin-arg INIT=CIRCLE \
            --plugin-arg RADIUS=100 \
            --plugin-arg PARAMS="$DATA/P_nicotianae_local_parameters.csv" \
            --plugin-arg QUANTILES="$DATA/P_nicotianae_empirical_quantiles.csv" \
            --plugin-arg MICRONS_PER_CELL=10 \
            --out "$BIN"

        # Export trajectories to an XML file.
        echo "[$SEED/$N_RUNS] Exporting trajectories to XML..."
        dune exec abca -- \
            --mode xml \
            --model zoospores-empirical \
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
