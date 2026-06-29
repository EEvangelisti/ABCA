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

exception Unknown_model of string
(** Raised when a requested model name is not present in the registry. *)

val register : Model.t -> unit
(** Registers a model.
    If another model with the same name already exists, it is replaced. *)

val find : string -> Model.t
(** Finds a registered model by name.
    Raises [Unknown_model] if no model has this name. *)

val exists : string -> bool
(** Returns [true] if a model with the given name is registered. *)

val all : unit -> Model.t list
(** Returns all registered models, sorted by family and then by name. *)

val by_family : Model.family -> Model.t list
(** Returns all registered models belonging to a given family. *)

val families : unit -> Model.family list
(** Returns the list of registered model families, without duplicates. *)

val names : unit -> string list
(** Returns the names of all registered models, sorted like {!all}. *)
