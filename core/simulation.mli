(* simulation.mli *)

type ('state, 'params) t

val create :
  model:string ->
  grid:Grid.t ->
  rule:('state, 'params) Rule.t ->
  params:'params ->
  ?keep_history:bool ->
  unit ->
  ('state, 'params) t

val model : ('state, 'params) t -> string
val engine : ('state, 'params) t -> ('state, 'params) Engine.t
val grid : ('state, 'params) t -> Grid.t
val generation : ('state, 'params) t -> int
val current : ('state, 'params) t -> 'state array array
val history : ('state, 'params) t -> 'state array array array option

val step : ('state, 'params) t -> ('state, 'params) t
val run : int -> ('state, 'params) t -> ('state, 'params) t
