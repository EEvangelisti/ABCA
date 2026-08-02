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
  --model zoospores-empirical-beads \
  --rows 400 \
  --cols 400 \
  --generations 200 \
  --agents 2000 \
  --seed 42 \
  --plugin-arg INIT=FULL \
  --plugin-arg PARAMS=$ROOT/empirical/data/P_nicotianae_local_parameters.csv \
  --plugin-arg QUANTILES=$ROOT/empirical/data/P_nicotianae_empirical_quantiles.csv \
  --plugin-arg MICRONS_PER_CELL=10 \
  --plugin-arg BEADS=FILE \
  --plugin-arg BEAD_MAP=$ROOT/examples/bead_map.csv \
  --plugin-arg BEAD_RADIUS=0.5 \
  --plugin-arg ZOOSPORE_RADIUS=0.5 \
  --plugin-arg BEAD_MIN_GAP=0.0 \
  --plugin-arg COLLISION_RESPONSE=BOTH \
  --plugin-arg COLLISION_SLOWDOWN=0.001 \
  --plugin-arg COLLISION_SPEED_FACTOR=0.001 \
  --out $ROOT/examples/P_nicotianae_empirical_beads.bin

"$ABCA" \
  --mode xml \
  --model zoospores-empirical-beads \
  --input $ROOT/examples/P_nicotianae_empirical_beads.bin \
  --xml $ROOT/examples/P_nicotianae_empirical_beads.xml

"$ABCA" \
  --mode render \
  --render-root $ROOT/examples \
  --model zoospores-empirical-beads \
  --input $ROOT/examples/P_nicotianae_empirical_beads.bin \
  --gif P_nicotianae_empirical_beads.gif \
  --palette python-binary \
  --background black \
  --every 1 \
  --fps 15
