#! /usr/bin/env bash

cd ../../..

dune exec abca -- \
  --mode run \
  --model life \
  --rows 200 \
  --cols 200 \
  --toroidal \
  --generations 200 \
  --density 0.10 \
  --seed 42 \
  --out plugins/life/examples/life.bin

dune exec abca -- \
  --mode render \
  --render-root plugins/life/examples \
  --input plugins/life/examples/life.bin \
  --gif life.gif \
  --palette tol-muted

cd plugins/life/examples
