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

type shape =
  | Full_grid
  | Disk of {
      center : Grid.coord option;
      radius : float;
    }
  | Ring of {
      center    : Grid.coord option;
      radius    : float;
      thickness : float;
    }
(** Initial geometric region from which coordinates can be selected.
    [Full_grid] selects every coordinate.
    [Disk] selects coordinates within [radius] of the center.
    [Ring] selects coordinates whose distance from the center lies within
    [thickness] around [radius].
    When [center] is [None], the grid center is used. *)

val select :
  Grid.t ->
  shape ->
  Grid.coord array
(** Returns all grid coordinates belonging to the requested shape. *)

val random_subset :
  Rng.t ->
  n:int ->
  Grid.coord array ->
  Grid.coord array
(** Returns up to [n] randomly selected coordinates from an array.
    The input array is copied before shuffling and is therefore left unchanged. *)
