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

"$ABCA" \
  --mode run \
  --model zoospores-hmm-beads \
  --rows 400 \
  --cols 400 \
  --generations 200 \
  --agents 2000 \
  --seed 42 \
  --toroidal \
  --plugin-arg INIT=FULL \
  --plugin-arg TRANSITIONS=$ROOT/hmm/data/P_nicotianae_hmm_transition_matrix.tsv \
  --plugin-arg START_PROBABILITIES=$ROOT/hmm/data/P_nicotianae_hmm_start_probabilities.tsv \
  --plugin-arg STATE_QUANTILES=$ROOT/hmm/data/P_nicotianae_hmm_state_quantiles.tsv \
  --plugin-arg MICRONS_PER_CELL=10 \
  --plugin-arg BEADS=FILE \
  --plugin-arg BEAD_MAP="/home/adunaton/Logiciels/ABCA/plugins/zoospores/examples/bead_map.csv" \
  --plugin-arg COLLISION_RESPONSE=BOTH \
  --plugin-arg COLLISION_SLOWDOWN=0.001 \
  --plugin-arg COLLISION_SPEED_FACTOR=0.001 \
  --out $ROOT/examples/P_nicotianae_hmm.bin

"$ABCA" \
  --mode xml \
  --model zoospores-hmm-beads \
  --input $ROOT/examples/P_nicotianae_hmm.bin \
  --xml $ROOT/examples/P_nicotianae_hmm.xml

"$ABCA" \
  --mode render \
  --render-root $ROOT/examples \
  --model zoospores-hmm-beads \
  --input $ROOT/examples/P_nicotianae_hmm.bin \
  --gif P_nicotianae_hmm.gif \
  --palette python-binary \
  --background black \
  --every 1 \
  --fps 15


