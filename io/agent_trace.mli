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

type record = {
  frame : int;
  id    : int;
  x     : float;
  y     : float;
  row   : int;
  col   : int;
  angle : int;
  age   : int;
  state : int;
}

type t = record array

val empty : t

