#!/usr/bin/env bash
set -euo pipefail

# Run from the plugin directory, as in the original script.
cd ../../..

dune build
ABCA="$(dune exec which abca 2>/dev/null)"
if [[ ! -x "$ABCA" ]]; then
  echo 'Error: ABCA executable not found' >&2
  exit 1
fi

ROOT="plugins/zoospores_AI"
OUT="$ROOT/examples"
mkdir -p "$OUT"

# Supply the frozen canonical portfolio TOML explicitly.
# Example: PARAMETER_FILE=plugins/zoospores_AI/parameters.toml ./zoospores_AI_all_13.sh
PARAMETER_FILE="${PARAMETER_FILE:-$ROOT/canonical_fit/canonical_parameters.toml}"
if [[ -z "$PARAMETER_FILE" || ! -f "$PARAMETER_FILE" ]]; then
  echo 'Set PARAMETER_FILE to the existing canonical portfolio TOML file.' >&2
  exit 1
fi

MODELS=(
  CAN-IID CAN-BALLISTIC CAN-PCRW CAN-TURN-AR1 CAN-VELOCITY-OU
  CAN-SPEED-TURN CAN-SWITCH-PAUSE CAN-SWITCH-TURN CAN-SWITCH-SPEED
  CAN-HET-SPEED CAN-REVERSAL CAN-EMP-LOCAL CAN-EMP-WHOLE
)

for MODEL in "${MODELS[@]}"; do
  echo "===== $MODEL ====="
  PREFIX="$OUT/P_nicotianae_${MODEL}"
  "$ABCA" --mode run --model "$MODEL" \
    --rows 2000 --cols 2000 --generations 100 --agents 1000 --seed 37 \
    --plugin-arg 'INIT=CIRCLE' --plugin-arg 'RADIUS=500' \
    --plugin-arg "PARAMETER_FILE=$PARAMETER_FILE" \
    --out "${PREFIX}.bin"

  "$ABCA" --mode xml --model "$MODEL" \
    --input "${PREFIX}.bin" --xml "${PREFIX}.xml"

  "$ABCA" --mode render --render plot --render-root "$OUT" \
    --model "$MODEL" --input "${PREFIX}.bin" --microns-per-cell 1

  "$ABCA" --mode render --render-root "$OUT" \
    --model "$MODEL" --input "${PREFIX}.bin" \
    --gif "Simulation_${MODEL}.gif" \
    --palette tol-prgn-binary --background white --every 1 --fps 15

done

echo 'All 13 models completed.'
