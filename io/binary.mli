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

module type STATE_CODEC = sig
  type t
  (** State type serialized in binary files. *)

  val to_int32 : t -> int32
  (** Converts a state value to its binary [int32] representation. *)

  val of_int32 : int32 -> t
  (** Reconstructs a state value from its binary [int32] representation. *)
end

type header = {
  version    : int;
  rows       : int;
  cols       : int;
  generation : int;
  frames     : int;
  metadata   : Metadata.t;
}
(** Header stored at the beginning of a binary simulation file. *)

type 'state archive = {
  header : header;
  frames : 'state array array array;
  agents : Agent_trace.t;
}
(** Complete simulation record stored in a binary file. *)

val make_archive :
  rows:int ->
  cols:int ->
  generation:int ->
  metadata:Metadata.t ->
  frames:'state array array array ->
  ?agents:Agent_trace.t ->
  unit -> 'state archive
(** Builds a complete simulation record from simulation frames, metadata,
    and optional agent trajectories.
    If omitted, [agents] defaults to an empty agent trace. *)

val version : int
(** Binary file format version. *)

val save :
  filename:string ->
  archive:'state archive ->
  codec:(module STATE_CODEC with type t = 'state) ->
  unit
(** Saves a complete simulation to a binary file. *)

val load :
  filename:string ->
  codec:(module STATE_CODEC with type t = 'state) ->
  'state archive
(** Loads a complete simulation from a binary file. *)

val load_frames :
  filename:string ->
  codec:(module STATE_CODEC with type t = 'state) ->
  header * 'state array array array * Agent_trace.t
(** Loads simulation frames from a binary file.
    Raises [Failure] if the file format, version, or header is invalid. *)
