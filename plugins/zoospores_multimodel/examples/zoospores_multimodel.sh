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

ROOT="plugins/zoospores_multimodel"

MODEL='c0_iid'
MODEL='c1_crw'
MODEL='c2_pair_bootstrap'
MODEL='c3_vector_bootstrap1'
MODEL='c4_prw'
MODEL='c5_ou_velocity'
MODEL='c6_markov2'
MODEL='c7_semimarkov2'

# Models were not fitted
#MODEL='c8_copula_var1'
#MODEL='c9_gaussian_hmm'

"$ABCA" \
  --mode run \
  --model 'zoospores-multimodel' \
  --rows 400 \
  --cols 400 \
  --generations 100 \
  --agents 1000 \
  --seed 37 \
  --plugin-arg INIT=DISK \
  --plugin-arg RADIUS=50 \
  --plugin-arg MICRONS_PER_CELL=10 \
  --plugin-arg MODEL="$MODEL" \
  --plugin-arg PARAMS="$ROOT/data/$MODEL.params" \
  --out $ROOT/examples/Zoospores_$MODEL.bin

"$ABCA" \
  --mode xml \
  --model 'zoospores-multimodel' \
  --input $ROOT/examples/Zoospores_$MODEL.bin \
  --xml $ROOT/examples/Zoospores_$MODEL.xml

"$ABCA" \
  --mode render \
  --render-root $ROOT/examples \
  --model 'zoospores-multimodel' \
  --input $ROOT/examples/Zoospores_$MODEL.bin \
  --gif Zoospores_$MODEL.gif \
  --palette magma \
  --background white \
  --every 1 \
  --fps 15


