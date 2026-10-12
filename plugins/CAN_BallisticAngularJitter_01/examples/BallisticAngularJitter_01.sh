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

ROOT="plugins/CAN_BallisticAngularJitter_01"

"$ABCA" \
  --mode run \
  --model "C3-CAN-BALLISTIC-ANGULAR-JITTER-01" \
  --rows 2000 \
  --cols 2000 \
  --generations 100 \
  --agents 1000 \
  --seed 37 \
  --plugin-arg "INIT=CIRCLE" \
  --plugin-arg "RADIUS=500" \
  --plugin-arg "PARAMETER_FILE=$ROOT/BallisticAngularJitter_01.toml" \
  --out $ROOT/examples/P_nicotianae_BallisticAngularJitter-01.bin

"$ABCA" \
  --mode xml \
  --model "C3-CAN-BALLISTIC-ANGULAR-JITTER-01" \
  --input $ROOT/examples/P_nicotianae_BallisticAngularJitter-01.bin \
  --xml $ROOT/examples/P_nicotianae_BallisticAngularJitter-01.xml

"$ABCA" \
  --mode render \
  --render plot \
  --render-root $ROOT/examples \
  --model "C3-CAN-BALLISTIC-ANGULAR-JITTER-01" \
  --input $ROOT/examples/P_nicotianae_BallisticAngularJitter-01.bin \
  --microns-per-cell 1

"$ABCA" \
  --mode render \
  --render-root $ROOT/examples \
  --model "C3-CAN-BALLISTIC-ANGULAR-JITTER-01" \
  --input $ROOT/examples/P_nicotianae_BallisticAngularJitter-01.bin \
  --gif P_nicotianae_BallisticAngularJitter-01.gif \
  --palette tol-prgn-binary \
  --background white \
  --every 1 \
  --fps 15


