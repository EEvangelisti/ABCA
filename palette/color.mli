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

type t = Abca_render.Png.color
(** RGB color represented by components in the range [[0.0, 1.0]]. *)

val black : t
(** Black color. *)

val white : t
(** White color. *)

val red : t
(** Red color. *)

val green : t
(** Green color. *)

val blue : t
(** Blue color. *)

val yellow : t
(** Yellow color. *)

val orange : t
(** Orange color. *)

val gray : t
(** Gray color. *)

val of_name : string -> t option
(** Converts a color name to a color, if recognized.
    Names are trimmed and matched case-insensitively.
    Both ["gray"] and ["grey"] are accepted. *)

val of_hex : string -> t option
(** Parses a hexadecimal color of the form ["RRGGBB"] or ["#RRGGBB"].
    Returns [None] if the string is not a valid hexadecimal color. *)

val parse : string -> t
(** Parses either a named color or a hexadecimal color.
    Raises [Invalid_argument] if the color is unknown or invalid. *)

val to_string : t -> string
(** Converts a color to an uppercase hexadecimal string of the form ["#RRGGBB"]. *)
