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

ROOT="plugins/zoospores_AI"

"$ABCA" \
  --mode run \
  --model 'zoospores_AI-v1.1' \
  --rows 400 \
  --cols 400 \
  --generations 100 \
  --agents 1000 \
  --seed 37 \
  --plugin-arg INIT=CIRCLE \
  --plugin-arg RADIUS=50 \
  --plugin-arg MICRONS_PER_CELL=10 \
  --out $ROOT/examples/P_nicotianae_zoospores_AI.bin

"$ABCA" \
  --mode xml \
  --model 'zoospores_AI-v1.1' \
  --input $ROOT/examples/P_nicotianae_zoospores_AI.bin \
  --xml $ROOT/examples/P_nicotianae_zoospores_AI.xml

"$ABCA" \
  --mode render \
  --render-root $ROOT/examples \
  --model 'zoospores_AI-v1.1' \
  --input $ROOT/examples/P_nicotianae_zoospores_AI.bin \
  --gif P_nicotianae_zoospores_AI.gif \
  --palette magma \
  --background white \
  --every 1 \
  --fps 15


