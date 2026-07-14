#!/usr/bin/env bash
set -euo pipefail

# Zoospores empirical
MODEL="zoospores-empirical"
BIN="${MODEL}.bin"
XML="${MODEL}_trajectories.xml"
GIF="${MODEL}.gif"
DATA="plugins/zoospores/empirical/data"

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
  --plugin-arg PARAMS=$DATA/abca_local_parameters.csv \
  --plugin-arg QUANTILES=$DATA/abca_empirical_quantiles.csv \
  --plugin-arg MICRONS_PER_CELL=10 \
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


