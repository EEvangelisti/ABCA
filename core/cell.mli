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

type state = int
(** Integer state stored in a cell.
    The interpretation of this value is left entirely to the plugin. *)

type flags = {
  active  : bool;
  dirty   : bool;
  blocked : bool;
}
(** Generic runtime flags associated with a cell.
    - [active] may be used to mark currently active cells.
    - [dirty] indicates that the cell has been modified since the previous step.
    - [blocked] can be used to prevent updates or movement. *)

type metadata = (string * string) list
(** Arbitrary key-value annotations attached to a cell.
    Plugins may use this to store custom information without extending
    the core cell representation. *)

type t
(** Opaque cell type. *)

val empty : t
(** The canonical empty cell.
    This cell has state [0], no metadata, and all flags set to [false]. *)

val create :
  ?active:bool ->
  ?dirty:bool ->
  ?blocked:bool ->
  ?metadata:metadata ->
  state ->
  t
(** Creates a new cell with the given state and optional attributes. *)

val state : t -> state
(** Returns the cell state. *)

val flags : t -> flags
(** Returns the cell flags. *)

val metadata : t -> metadata
(** Returns the cell metadata. *)

val is_empty : t -> bool
(** Returns [true] if the cell is identical to {!empty}. *)

val is_active : t -> bool
(** Returns the value of the [active] flag. *)

val is_dirty : t -> bool
(** Returns the value of the [dirty] flag. *)

val is_blocked : t -> bool
(** Returns the value of the [blocked] flag. *)

val with_state : state -> t -> t
(** Returns a copy of the cell with a new state.
    The returned cell is automatically marked as dirty. *)

val with_flags : flags -> t -> t
(** Returns a copy of the cell with new flags. *)

val with_metadata : metadata -> t -> t
(** Returns a copy of the cell with new metadata. *)

val set_active : bool -> t -> t
(** Sets the [active] flag. *)

val set_dirty : bool -> t -> t
(** Sets the [dirty] flag. *)

val set_blocked : bool -> t -> t
(** Sets the [blocked] flag. *)

val add_metadata : string -> string -> t -> t
(** Associates a metadata value with a key.
    Any existing value for the same key is replaced. *)

val remove_metadata : string -> t -> t
(** Removes the metadata entry associated with a key. *)

val metadata_opt : string -> t -> string option
(** Returns the value associated with a metadata key, if present. *)

val clear_metadata : t -> t
(** Removes all metadata from the cell. *)

val equal : t -> t -> bool
(** Structural equality between two cells. *)
