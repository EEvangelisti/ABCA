type family =
  | Life_like
  | Larger_than_life
  | Cyclic
  | Weighted_life
  | Generations
  | Agent_based
  | Biological
  | Other of string
(** Broad family to which a model belongs.
    [Other] allows external or plugin-defined families. *)

type simulation_kind =
  | Cellular_automaton
  | Agent_based_model
  | Hybrid_model
(** General simulation paradigm used by the model. *)

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
    agents:int option ->
    topology:Abca.Grid.topology ->
    output:string ->
    unit;

  export_xml :
    input:string ->
    output:string ->
    unit;
}
(** Registered model descriptor.
    It stores metadata, rendering information, and executable entry points
    for running the model and exporting its results. *)

val family_to_string : family -> string
(** Converts a model family to a human-readable string. *)

val kind_to_string : simulation_kind -> string
(** Converts a simulation kind to a human-readable string. *)

val short_label : t -> string
(** Returns a compact label combining the model name, family, and kind. *)
