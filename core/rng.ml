(*
 * ABCA (Agent-Based Cellular Automata)
 * A modular simulation framework for discrete spatial systems,
 * ranging from classical cellular automata to biologically inspired
 * agent-based models.
 *
 * Copyright (c) 2026 Edouard Evangelisti
 *
 * Distributed under the MIT License.
 * This software is provided "as is", without warranty of any kind.
 * See the LICENSE file for details.
 *)

type t = {
  seed  : int;
  state : Random.State.t;
}

let create seed =
  {
    seed;
    state = Random.State.make [| seed |];
  }

let seed rng =
  rng.seed

let copy rng =
  {
    seed = rng.seed;
    state = Random.State.copy rng.state;
  }

let int rng bound =
  if bound <= 0 then
    invalid_arg "Rng.int: bound must be positive";
  Random.State.int rng.state bound

let float rng bound =
  if bound <= 0.0 then
    invalid_arg "Rng.float: bound must be positive";
  Random.State.float rng.state bound

let bool rng =
  Random.State.bool rng.state

let chance rng p =
  if p < 0.0 || p > 1.0 then
    invalid_arg "Rng.chance: probability must be between 0 and 1";
  Random.State.float rng.state 1.0 < p

let range_int rng ~min ~max =
  if max < min then
    invalid_arg "Rng.range_int: max must be >= min";
  min + int rng (max - min + 1)

let range_float rng ~min ~max =
  if max < min then
    invalid_arg "Rng.range_float: max must be >= min";
  min +. float rng (max -. min)

let choose rng arr =
  if Array.length arr = 0 then
    invalid_arg "Rng.choose: empty array";
  arr.(int rng (Array.length arr))

let shuffle_array rng arr =
  for i = Array.length arr - 1 downto 1 do
    let j = int rng (i + 1) in
    let tmp = arr.(i) in
    arr.(i) <- arr.(j);
    arr.(j) <- tmp
  done
