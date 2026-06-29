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

val make_gif :
  ?log_file:string ->
  fps:int ->
  png_dir:string ->
  prefix:string ->
  output:string ->
  unit -> unit
(** Creates an animated GIF from a sequence of PNG images using FFmpeg.
    Input images must be named ["<prefix>_000001.png"], ["<prefix>_000002.png"], etc.
    A temporary palette is generated automatically to improve image quality.
    Raises [Invalid_argument] if [fps] is not positive.
    Terminates the program if an FFmpeg command fails. *)

val make_mp4 :
  ?log_file:string ->
  fps:int ->
  png_dir:string ->
  prefix:string ->
  output:string ->
  unit -> unit
(** Creates an MP4 video from a sequence of PNG images using FFmpeg.
    Input images must be named ["<prefix>_000001.png"], ["<prefix>_000002.png"], etc.
    The output is encoded with H.264 using the YUV420P pixel format for
    broad compatibility.
    Raises [Invalid_argument] if [fps] is not positive.
    Terminates the program if an FFmpeg command fails. *)
