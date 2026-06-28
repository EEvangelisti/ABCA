module type S = sig
  type state
  (** Cell state manipulated by the rule. *)

  type params
  (** Parameter type controlling the rule. *)

  val name : string
  (** Human-readable name of the rule. *)

  val initial :
    params ->
    Grid.t ->
    state array array
  (** Creates the initial simulation state for a given grid. *)

  val next :
    params ->
    Grid.t ->
    state array array ->
    Grid.coord ->
    state
  (** Computes the next state of a single cell.
      The function is given the rule parameters, the grid, the current
      simulation frame, and the coordinate of the cell to update. *)
end

type ('state, 'params) t = {
  name    : string;
  initial : 'params -> Grid.t -> 'state array array;
  next    : 'params -> Grid.t -> 'state array array -> Grid.coord -> 'state;
}
(** First-class representation of a cellular automaton rule. *)

val of_module :
  (module S with type state = 'state and type params = 'params) ->
  ('state, 'params) t
(** Converts a module implementing {!S} into a first-class rule value. *)
