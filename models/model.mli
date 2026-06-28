(* models/model.mli *)

type family =
  | Life_like
  | Larger_than_life
  | Cyclic
  | Weighted_life
  | Generations
  | Agent_based
  | Biological
  | Other of string

type simulation_kind =
  | Cellular_automaton
  | Agent_based_model
  | Hybrid_model

type t = {
  name        : string;
  family      : family;
  kind        : simulation_kind;
  description : string;

  state_count : int;
  to_color_index : int -> int;

  run :
    rows:int ->
    cols:int ->
    generations:int ->
    seed:int ->
    density:float ->
    agents: int option -> 
    topology:Abca.Grid.topology ->
    output:string ->
    unit;

  export_xml :
    input:string ->
    output:string ->
    unit;
}

val family_to_string : family -> string

val kind_to_string : simulation_kind -> string

val short_label : t -> string
