#! /usr/bin/env bash

cd ../../..

dune exec abca -- \
  --mode run \
  --model diamoeba \
  --rows 200 \
  --cols 200 \
  --toroidal \
  --generations 200 \
  --density 0.48 \
  --seed 42 \
  --out plugins/life/examples/diamoeba.bin

dune exec abca -- \
  --mode render \
  --render-root plugins/life/examples \
  --input plugins/life/examples/diamoeba.bin \
  --gif diamoeba.gif \
  --palette inferno \
  --every 5

cd plugins/life/examples
