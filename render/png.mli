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

type color = float * float * float
(** RGB components in [0,1]. *)

type palette = { background : color; colors : color array }

val default_palette : palette

val save_frame :
  filename:string -> cell_size:int -> ?background:color ->
  palette:palette -> to_color_index:('state -> int option) ->
  'state array array -> unit
(** Render one square-cell grid as a PNG, without antialiasing. *)

val save_frames :
  dirname:string -> prefix:string -> every:int -> cell_size:int ->
  ?background:color -> palette:palette ->
  to_color_index:('state -> int option) -> 'state array array array -> unit
(** Render selected grid frames as numbered PNG files. *)
