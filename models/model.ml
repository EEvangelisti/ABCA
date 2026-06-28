(* models/model.ml *)

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
    topology:Abca.Grid.topology ->
    output:string ->
    unit;

  export_xml :
    input:string ->
    output:string ->
    unit;
}

let family_to_string = function
  | Life_like -> "life-like"
  | Larger_than_life -> "larger-than-life"
  | Cyclic -> "cyclic"
  | Weighted_life -> "weighted-life"
  | Generations -> "generations"
  | Agent_based -> "agent-based"
  | Biological -> "biological"
  | Other s -> s

let kind_to_string = function
  | Cellular_automaton -> "cellular automaton"
  | Agent_based_model -> "agent-based model"
  | Hybrid_model -> "hybrid model"

let short_label model =
  Printf.sprintf "%s [%s / %s]"
    model.name
    (family_to_string model.family)
    (kind_to_string model.kind)
