#!/usr/bin/env bash
set -euo pipefail

# Zoospores HMM
MODEL="zoospores-hmm"
BIN="${MODEL}.bin"
XML="${MODEL}_trajectories.xml"
GIF="${MODEL}.gif"
DATA="plugins/zoospores/hmm/data"

dune clean
rm -f "$BIN" "$XML" "$GIF"

dune exec abca -- \
  --mode run \
  --model "$MODEL" \
  --rows 300 \
  --cols 300 \
  --generations 50 \
  --agents 500 \
  --seed 42 \
  --plugin-arg INIT=CIRCLE \
  --plugin-arg RADIUS=80 \
  --plugin-arg TRANSITIONS=$DATA/hmm_transition_matrix.tsv \
  --plugin-arg START_PROBABILITIES=$DATA/hmm_start_probabilities.tsv \
  --plugin-arg STATE_QUANTILES=$DATA/hmm_state_quantiles.tsv \
  --plugin-arg MICRONS_PER_CELL=10 \
  --plugin-arg DT=0.22 \
  --out "$BIN"

dune exec abca -- \
  --mode xml \
  --model "$MODEL" \
  --input "$BIN" \
  --xml "$XML"

dune exec abca -- \
  --mode render \
  --model "$MODEL" \
  --input "$BIN" \
  --gif "$GIF" \
  --palette grayscale \
  --background black \
  --every 1 \
  --fps 15


