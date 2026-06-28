(* rule.ml *)

module type S = sig
  type state
  type params

  val name : string

  val initial :
    params ->
    Grid.t ->
    state array array

  val next :
    params ->
    Grid.t ->
    state array array ->
    Grid.coord ->
    state
end

type ('state, 'params) t = {
  name    : string;
  initial : 'params -> Grid.t -> 'state array array;
  next    : 'params -> Grid.t -> 'state array array -> Grid.coord -> 'state;
}

let of_module
    (type state)
    (type params)
    (module R : S with type state = state and type params = params) =
  {
    name = R.name;
    initial = R.initial;
    next = R.next;
  }
