#! /usr/bin/env bash

cd ../../..

dune exec abca -- \
  --mode run \
  --model cyc-spirals \
  --rows 200 \
  --cols 200 \
  --generations 50 \
  --toroidal \
  --density 1.0 \
  --seed 42 \
  --out plugins/cyclic/examples/spirals.bin

dune exec abca -- \
  --mode render \
  --input plugins/cyclic/examples/spirals.bin \
  --gif spirals.gif \
  --palette viridis

cd plugins/cyclic/examples
