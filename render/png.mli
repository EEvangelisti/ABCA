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
(** RGB color with components in the range [[0.0, 1.0]]. *)

type palette = {
  background : color;
  colors     : color array;
}
(** Rendering palette.
    [background] is used to clear the image before drawing.
    [colors] maps color indices returned by [to_color_index] to RGB values. *)

val default_palette : palette
(** Default black-and-white rendering palette. *)

val save_frame :
  filename:string ->
  cell_size:int ->
  ?background:color ->
  palette:palette ->
  to_color_index:('state -> int option) ->
  'state array array ->
  unit
(** Renders a simulation frame as a PNG image.
    Each cell is drawn as a square of size [cell_size] pixels.
    If provided, [background] overrides the palette background.
    Cells whose color index equals [skip_index] are omitted.
    Raises [Invalid_argument] if the frame is empty, irregular, [cell_size]
    is not positive, or a color index is outside the palette. *)

val save_frames :
  dirname:string ->
  prefix:string ->
  every:int ->
  cell_size:int ->
  ?background:color ->
  palette:palette ->
  to_color_index:('state -> int option) ->
  'state array array array ->
  unit
(** Renders a sequence of frames as numbered PNG images.
    Images are written as ["<prefix>_000000.png"], ["<prefix>_000001.png"], etc.
    Only every [every]-th frame is exported.
    The output directory is created if necessary.
    Raises [Invalid_argument] if [every] or [cell_size] is not positive,
    or if any frame is invalid. *)
