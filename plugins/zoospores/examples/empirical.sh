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
  --model zoospores-empirical \
  --rows 200 \
  --cols 200 \
  --generations 100 \
  --agents 1000 \
  --seed 37 \
  --toroidal \
  --plugin-arg INIT=CIRCLE \
  --plugin-arg RADIUS=50 \
  --plugin-arg PARAMS=$ROOT/empirical/data/P_nicotianae_local_parameters.csv \
  --plugin-arg QUANTILES=$ROOT/empirical/data/P_nicotianae_empirical_quantiles.csv \
  --plugin-arg MICRONS_PER_CELL=10 \
  --out $ROOT/examples/P_nicotianae_empirical.bin

"$ABCA" \
  --mode xml \
  --model zoospores-empirical \
  --input $ROOT/examples/P_nicotianae_empirical.bin \
  --xml $ROOT/examples/P_nicotianae_empirical.xml

"$ABCA" \
  --mode render \
  --render-root $ROOT/examples \
  --model zoospores-empirical \
  --input $ROOT/examples/P_nicotianae_empirical.bin \
  --gif P_nicotianae_empirical.gif \
  --palette tol-prgn-binary \
  --background white \
  --every 1 \
  --fps 15


