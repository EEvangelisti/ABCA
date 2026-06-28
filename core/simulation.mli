type ('state, 'params) t
(** Simulation wrapper associating a model name with a simulation engine. *)

val create :
  model:string ->
  grid:Grid.t ->
  rule:('state, 'params) Rule.t ->
  params:'params ->
  ?keep_history:bool ->
  unit ->
  ('state, 'params) t
(** Creates a simulation from a model name, a grid, a rule, and its parameters.
    History is kept by default. *)

val model : ('state, 'params) t -> string
(** Returns the model name associated with the simulation. *)

val engine : ('state, 'params) t -> ('state, 'params) Engine.t
(** Returns the underlying simulation engine. *)

val grid : ('state, 'params) t -> Grid.t
(** Returns the grid used by the simulation. *)

val generation : ('state, 'params) t -> int
(** Returns the current generation number. *)

val current : ('state, 'params) t -> 'state array array
(** Returns the current simulation frame. *)

val history : ('state, 'params) t -> 'state array array array option
(** Returns the recorded frames, if history is enabled. *)

val step : ('state, 'params) t -> ('state, 'params) t
(** Advances the simulation by one generation. *)

val run : int -> ('state, 'params) t -> ('state, 'params) t
(** Advances the simulation by [n] generations.
    Raises [Invalid_argument] if [n] is negative. *)
