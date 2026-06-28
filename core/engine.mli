(* engine.mli *)

type ('state, 'params) t

val create :
  grid:Grid.t ->
  rule:('state, 'params) Rule.t ->
  params:'params ->
  ?keep_history:bool ->
  unit ->
  ('state, 'params) t

val grid : ('state, 'params) t -> Grid.t

val rule_name : ('state, 'params) t -> string

val params : ('state, 'params) t -> 'params

val generation : ('state, 'params) t -> int

val current : ('state, 'params) t -> 'state array array

val history : ('state, 'params) t -> 'state array array array option

val step : ('state, 'params) t -> ('state, 'params) t

val run : int -> ('state, 'params) t -> ('state, 'params) t
