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
  (** State type serialized to XML. *)

  val to_string : t -> string
  (** Converts a state value to its XML string representation. *)
end

val save_frames :
  filename:string ->
  model:string ->
  grid:Abca.Grid.t ->
  generation:int ->
  frames:'state array array array ->
  codec:(module STATE_CODEC with type t = 'state) ->
  unit
(** Saves simulation frames as an XML document.
    Only non-empty cells are written to the output, reducing file size.
    All frames must match the dimensions of [grid].
    Raises [Invalid_argument] if any frame has an invalid shape. *)

val save_agent_trace_trackmate :
  filename:string ->
  Agent_trace.t ->
  unit
(** Saves an agent trace as a simple particle-tracking XML file.
    The output uses [particle] elements containing [detection] elements
    with [t], [x], and [y] attributes, suitable for trajectory-analysis scripts. *)
