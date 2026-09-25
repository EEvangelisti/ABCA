open Abca
module Model = Zoospores_AI_model

type state = Model.state
let model_name = "zoospores_AI-v1.1"

let find_arg key plugin_args =
  List.assoc_opt (String.uppercase_ascii key) plugin_args

let arg_string key default plugin_args =
  match find_arg key plugin_args with
  | Some x -> x
  | None -> default

let arg_int key default plugin_args =
  match find_arg key plugin_args with
  | Some x -> int_of_string x
  | None -> default

let arg_float key default plugin_args =
  match find_arg key plugin_args with
  | Some x -> float_of_string x
  | None -> default

let default_initial_speeds_file =
  Filename.concat "plugins/zoospores_AI/data" "initial_training_speeds.csv"

let parse_speed_line line =
  let s = String.trim line in
  if s = "" then None
  else
    let first =
      match String.index_opt s ',' with
      | Some i -> String.sub s 0 i
      | None -> s
    in
    try Some (float_of_string (String.trim first))
    with Failure _ -> None

let load_initial_speeds filename =
  let ic =
    try open_in filename
    with Sys_error msg ->
      failwith
        ("Zoospore discovered: cannot open initial-speed file "
         ^ filename ^ ": " ^ msg)
  in
  let values = ref [] in
  Fun.protect
    ~finally:(fun () -> close_in_noerr ic)
    (fun () ->
       try
         while true do
           match parse_speed_line (input_line ic) with
           | Some x when x >= 0.0 -> values := x :: !values
           | Some _ ->
               failwith
                 "Zoospore discovered: initial speeds must be non-negative"
           | None -> ()
         done
       with End_of_file -> ());
  let result = Array.of_list (List.rev !values) in
  if Array.length result = 0 then
    failwith
      ("Zoospore discovered: no numeric speeds found in " ^ filename);
  result

module Binary_codec = struct
  type t = state
  let to_int32 = Int32.of_int
  let of_int32 = Int32.to_int
end

module Xml_codec = struct
  type t = state
  let to_string = string_of_int
end

let to_color_index = function
  | 0 -> None
  | _ -> Some 0

let metadata params ~rows ~cols ~generations ~density =
  Abca_io.Metadata.of_list [
    "model", model_name;
    "family", "biological";
    "kind", "agent-based";
    "rows", string_of_int rows;
    "cols", string_of_int cols;
    "generations", string_of_int generations;
    "seed", string_of_int params.Model.seed;
    "density", string_of_float density;
    "agents", string_of_int params.agents;
    "topology",
      (match params.topology with
       | Grid.Bounded -> "bounded"
       | Grid.Toroidal -> "toroidal");
    "initial_speeds_file", params.initial_speeds_file;
    "initial_speed_count", string_of_int (Array.length params.initial_speeds);
    "time_step_s", string_of_float params.dt;
    "microns_per_cell", string_of_float params.microns_per_cell;
    "init", Model.string_of_init_shape params.init_shape;
    "radius", string_of_float params.radius;
    "thickness", string_of_float params.thickness;
    "movement_model",
      "frozen discovered-swimming-v1.1 regression";
    "predictors",
      "log(speed), log(speed)^2, sin(previous_turn), cos(previous_turn)";
    "outputs",
      "log(next_speed+eps), cos(turn), sin(turn)";
    "agent_cell_exclusion", "false";
  ]

let run
    ~rows ~cols ~generations ~seed ~density ~agents ~topology
    ~plugin_args ~output =
  let initial_speeds_file =
    arg_string "INITIAL_SPEEDS" default_initial_speeds_file plugin_args
  in
  let initial_speeds = load_initial_speeds initial_speeds_file in
  let params : Model.params = {
    initial_speeds;
    initial_speeds_file;
    agents =
      (match agents with
       | Some n -> n
       | None -> arg_int "AGENTS" 200 plugin_args);
    init_shape =
      Model.parse_init_shape (arg_string "INIT" "FULL" plugin_args);
    radius = arg_float "RADIUS" 60.0 plugin_args;
    thickness = arg_float "THICKNESS" 4.0 plugin_args;
    microns_per_cell =
      arg_float "MICRONS_PER_CELL" 1.0 plugin_args;
    dt = arg_float "DT" 0.0700506 plugin_args;
    max_age = arg_int "MAX_AGE" 255 plugin_args;
    seed;
    topology;
  } in
  if params.microns_per_cell <= 0.0 then
    invalid_arg "Zoospore discovered: MICRONS_PER_CELL must be positive";
  if params.dt <= 0.0 then
    invalid_arg "Zoospore discovered: DT must be positive";
  if params.agents < 0 then
    invalid_arg "Zoospore discovered: AGENTS must be non-negative";
  let grid = Grid.create ~topology ~rows ~cols () in
  let frames, agent_trace =
    Model.simulate params grid generations
  in
  let archive =
    Abca_io.Binary.make_archive
      ~rows
      ~cols
      ~generation:generations
      ~metadata:(metadata params ~rows ~cols ~generations ~density)
      ~frames
      ~agents:agent_trace
      ()
  in
  Abca_io.Binary.save
    ~filename:output
    ~archive
    ~codec:(module Binary_codec)

let export_xml ~input ~output =
  let open Abca_io.Binary in
  let archive =
    load ~filename:input ~codec:(module Binary_codec)
  in
  Abca_io.Xml.save_agent_trace_trackmate
    ~filename:output
    archive.agents

let model = {
  Abca_models.Model.name = model_name;
  family = Abca_models.Model.Biological;
  kind = Abca_models.Model.Agent_based_model;
  description =
    "AI-discovered zoospore swimming rule implemented in the standard ABCA simulation pipeline";
  state_count = 1;
  to_color_index;
  run;
  export_xml;
}

let models = [ model ]
