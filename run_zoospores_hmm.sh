#!/usr/bin/env bash
set -euo pipefail

MODEL="zoospores-hmm"
SPECIES="$1"
GEN="$2"
DATA="plugins/zoospores/hmm/data"

dune clean

dune exec abca -- \
  --mode render \
  --model "zoospores-hmm" \
  --input "zoospores-hmm_Ppar_100_000042.bin" \
  --gif "zoospores-hmm_Ppar_100_000042.gif" \
  --palette python-binary \
  --background black \
  --draw-background \
  --every 1 \
  --fps 15

exit 0

for I in $(seq 1 100); do

  INDEX="$(printf "%06d" $I)"
  BIN="${MODEL}_${SPECIES}_${GEN}_${INDEX}.bin"
  XML="${MODEL}_trajectories_${SPECIES}_${GEN}_${INDEX}.xml"

  dune exec abca -- \
    --mode run \
    --model "$MODEL" \
    --rows 1000 \
    --cols 1000 \
    --generations $GEN \
    --agents 2500 \
    --seed $I \
    --toroidal \
    --plugin-arg INIT=CIRCLE \
    --plugin-arg RADIUS=100 \
    --plugin-arg TRANSITIONS=$DATA/$SPECIES/hmm_transition_matrix.tsv \
    --plugin-arg START_PROBABILITIES=$DATA/$SPECIES/hmm_start_probabilities.tsv \
    --plugin-arg STATE_QUANTILES=$DATA/$SPECIES/hmm_state_quantiles.tsv \
    --plugin-arg MICRONS_PER_CELL=10 \
    --plugin-arg DT=0.07 \
    --out "z_binary/$BIN"

  dune exec abca -- \
    --mode xml \
    --model "$MODEL" \
    --input "z_binary/$BIN" \
    --xml "z_xml/$XML"

done
