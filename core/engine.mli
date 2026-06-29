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

type ('state, 'params) t
(** Simulation engine carrying the grid, rule, parameters, current frame,
    generation counter, and optional history. *)

val create :
  grid:Grid.t ->
  rule:('state, 'params) Rule.t ->
  params:'params ->
  ?keep_history:bool ->
  unit ->
  ('state, 'params) t
(** Creates a new engine from a grid, a rule, and its parameters.
    The initial frame is produced by the rule. History is kept by default. *)

val grid : ('state, 'params) t -> Grid.t
(** Returns the grid associated with the engine. *)

val rule_name : ('state, 'params) t -> string
(** Returns the name of the rule used by the engine. *)

val params : ('state, 'params) t -> 'params
(** Returns the parameters used by the rule. *)

val generation : ('state, 'params) t -> int
(** Returns the current generation number. *)

val current : ('state, 'params) t -> 'state array array
(** Returns the current simulation frame. *)

val history : ('state, 'params) t -> 'state array array array option
(** Returns the recorded frames, from oldest to newest, if history is enabled. *)

val step : ('state, 'params) t -> ('state, 'params) t
(** Advances the simulation by one generation. *)

val run : int -> ('state, 'params) t -> ('state, 'params) t
(** Advances the simulation by [n] generations.
    Raises [Invalid_argument] if [n] is negative. *)
