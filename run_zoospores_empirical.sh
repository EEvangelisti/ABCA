#!/usr/bin/env bash
set -euo pipefail

MODEL="zoospores-empirical"
SPECIES="$1"
GEN="$2"
BIN="${MODEL}_${SPECIES}_${GEN}.bin"
XML="${MODEL}_trajectories_${SPECIES}_${GEN}.xml"
GIF="${MODEL}_${SPECIES}_${GEN}.gif"
DATA="plugins/zoospores/empirical/data"

dune clean

dune exec abca -- \
  --mode run \
  --model "$MODEL" \
  --rows 1000 \
  --cols 1000 \
  --generations $GEN \
  --agents 2500 \
  --seed 42 \
  --toroidal \
  --plugin-arg INIT=CIRCLE \
  --plugin-arg RADIUS=100 \
  --plugin-arg PARAMS=$DATA/$SPECIES/abca_local_parameters.csv \
  --plugin-arg QUANTILES=$DATA/$SPECIES/abca_empirical_quantiles.csv \
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
  --palette tol-prgn-binary \
  --background white \
  --draw-background \
  --every 1 \
  --fps 15


