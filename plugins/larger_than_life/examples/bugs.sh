#! /usr/bin/env bash

cd ../../..

dune exec abca -- \
  --mode run \
  --model ltl-bugs \
  --rows 200 \
  --cols 200 \
  --generations 100 \
  --toroidal \
  --density 0.4 \
  --seed 42 \
  --out plugins/larger_than_life/examples/bugs.bin

dune exec abca -- \
  --mode render \
  --input plugins/larger_than_life/examples/bugs.bin \
  --gif bugs.gif \
  --palette python-binary

cd plugins/larger_than_life/examples
