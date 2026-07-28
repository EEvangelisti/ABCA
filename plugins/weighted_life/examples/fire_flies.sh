#! /usr/bin/env bash

cd ../../..

dune exec abca -- \
  --mode run \
  --model wlf-fire-flies \
  --rows 200 \
  --cols 200 \
  --generations 50 \
  --toroidal \
  --density 0.4 \
  --seed 42 \
  --out plugins/weighted_life/examples/fire_flies.bin

dune exec abca -- \
  --mode render \
  --render-root plugins/weighted_life/examples \
  --input plugins/weighted_life/examples/fire_flies.bin \
  --gif fire_flies.gif \
  --palette tol-muted

cd plugins/weighted_life/examples
