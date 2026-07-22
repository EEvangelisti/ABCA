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
#rm -f "$BIN" "$XML" "$GIF"


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


