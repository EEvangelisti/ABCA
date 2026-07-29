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
  --model zoospores-hmm \
  --rows 400 \
  --cols 400 \
  --generations 100 \
  --agents 2000 \
  --seed 42 \
  --toroidal \
  --plugin-arg INIT=CIRCLE \
  --plugin-arg RADIUS=75 \
  --plugin-arg TRANSITIONS=$ROOT/hmm/data/P_nicotianae_hmm_transition_matrix.tsv \
  --plugin-arg START_PROBABILITIES=$ROOT/hmm/data/P_nicotianae_hmm_start_probabilities.tsv \
  --plugin-arg STATE_QUANTILES=$ROOT/hmm/data/P_nicotianae_hmm_state_quantiles.tsv \
  --plugin-arg MICRONS_PER_CELL=10 \
  --out $ROOT/examples/P_nicotianae_hmm.bin

"$ABCA" \
  --mode xml \
  --model zoospores-hmm \
  --input $ROOT/examples/P_nicotianae_hmm.bin \
  --xml $ROOT/examples/P_nicotianae_hmm.xml

"$ABCA" \
  --mode render \
  --render-root $ROOT/examples \
  --model zoospores-hmm \
  --input $ROOT/examples/P_nicotianae_hmm.bin \
  --gif P_nicotianae_hmm.gif \
  --palette python-binary \
  --background black \
  --every 1 \
  --fps 15


