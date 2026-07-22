#!/usr/bin/env bash
set -euo pipefail

MODEL="${1:-life}"
GEN="${2:-100}"
BIN="${MODEL}_${GEN}.bin"
GIF="${MODEL}_${GEN}.gif"

dune clean

dune exec abca -- \
  --mode run \
  --model "$MODEL" \
  --density 0.1 \
  --generations $GEN \
  --seed 42 \
  --toroidal \
  --out "$BIN"

dune exec abca -- \
  --mode render \
  --model "$MODEL" \
  --input "$BIN" \
  --gif "$GIF" \
  --palette tol-prgn \
  --background white \
  --draw-background \
  --every 1 \
  --fps 15


