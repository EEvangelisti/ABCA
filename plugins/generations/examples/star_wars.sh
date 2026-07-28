#! /usr/bin/env bash

cd ../../..

dune exec abca -- \
  --mode run \
  --model gen-star-wars \
  --rows 200 \
  --cols 200 \
  --generations 100 \
  --toroidal \
  --density 0.2 \
  --seed 42 \
  --out plugins/generations/examples/star_wars.bin

dune exec abca -- \
  --mode render \
  --input plugins/generations/examples/star_wars.bin \
  --gif star_wars.gif \
  --palette tol-muted

cd plugins/generations/examples
