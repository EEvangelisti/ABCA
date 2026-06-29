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

module type S = sig
  type state
  type params

  val name : string

  val initial :
    params ->
    Grid.t ->
    state array array

  val next :
    params ->
    Grid.t ->
    state array array ->
    Grid.coord ->
    state
end

type ('state, 'params) t = {
  name    : string;
  initial : 'params -> Grid.t -> 'state array array;
  next    : 'params -> Grid.t -> 'state array array -> Grid.coord -> 'state;
}

let of_module
    (type state)
    (type params)
    (module R : S with type state = state and type params = params) =
  {
    name = R.name;
    initial = R.initial;
    next = R.next;
  }
