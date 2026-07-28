#! /usr/bin/env bash

cd ../../..

dune exec abca -- \
  --mode run \
  --model cyc-lava-lamp \
  --rows 200 \
  --cols 200 \
  --generations 50 \
  --toroidal \
  --density 1.0 \
  --seed 42 \
  --out plugins/cyclic/examples/lava-lamp.bin

dune exec abca -- \
  --mode render \
  --input plugins/cyclic/examples/lava-lamp.bin \
  --gif lava-lamp.gif \
  --palette viridis

cd plugins/cyclic/examples
