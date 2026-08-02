(*
 * Empirical zoospore plugin for ABCA.
 *
 * Biological movement parameters, including the complete latent VAR(1)
 * matrices A, Q and R, are loaded from abca_local_parameters.csv.
 * No global trajectory statistic (MSD,
 * straightness, tortuosity or net displacement) is imposed.
 *
 * Distributional assumptions are documented in
 * zoospores_empirical_assumptions.md.
 *)

open Abca
module Data = Zoospores_empirical_beads_data
module Model = Zoospores_empirical_beads_model

type state = Model.state

let model_name = "zoospores-empirical-beads"

let find_arg key plugin_args =
  List.assoc_opt (String.uppercase_ascii key) plugin_args

let arg_string key default plugin_args =
  match find_arg key plugin_args with Some x -> x | None -> default

let arg_int key default plugin_args =
  match find_arg key plugin_args with Some x -> int_of_string x | None -> default

let arg_float key default plugin_args =
  match find_arg key plugin_args with Some x -> float_of_string x | None -> default

module Binary_codec = struct
  type t = state
  let to_int32 x = Int32.of_int x
  let of_int32 x = Int32.to_int x
end

module Xml_codec = struct
  type t = state
  let to_string = string_of_int
end

let to_color_index = function
  | 0 -> None
  | s -> Some (min (s - 1) 255)

let metadata params ~rows ~cols ~generations ~density =
  let e = params.Model.empirical in
  Abca_io.Metadata.of_list [
    "model", model_name;
    "family", "biological";
    "kind", "agent-based";
    "rows", string_of_int rows;
    "cols", string_of_int cols;
    "generations", string_of_int generations;
    "seed", string_of_int params.seed;
    "density", string_of_float density;
    "agents", string_of_int params.agents;
    "topology", (match params.topology with Grid.Bounded -> "bounded" | Grid.Toroidal -> "toroidal");
    "parameter_file", params.parameter_file;
    "quantile_file", params.quantile_file;
    "time_step_s", string_of_float e.dt;
    "microns_per_cell", string_of_float params.microns_per_cell;
    "init", Model.string_of_init_shape params.init_shape;
    "radius", string_of_float params.radius;
    "thickness", string_of_float params.thickness;
    "beads", Model.string_of_bead_source params.bead_source;
    "bead_radius_cells", string_of_float params.bead_radius;
    "zoospore_radius_cells", string_of_float params.zoospore_radius;
    "bead_min_gap_cells", string_of_float params.bead_min_gap;
    "collision_response", Model.string_of_collision_response params.collision_response;
    "collision_slowdown", string_of_float params.collision_slowdown;
    "distribution_speed", "full inverse empirical CDF from abca_empirical_quantiles.csv";
    "dependence_model", "stationary bivariate Gaussian VAR(1): Z(t+1)=A Z(t)+epsilon, epsilon~N(0,Q)";
    "distribution_turn", "full inverse empirical CDF of absolute turn angle";
    "latent_A_11", string_of_float e.a11;
    "latent_A_12", string_of_float e.a12;
    "latent_A_21", string_of_float e.a21;
    "latent_A_22", string_of_float e.a22;
    "latent_Q_11", string_of_float e.q11;
    "latent_Q_12", string_of_float e.q12;
    "latent_Q_22", string_of_float e.q22;
    "latent_R_11", string_of_float e.r11;
    "latent_R_12", string_of_float e.r12;
    "latent_R_22", string_of_float e.r22;
    "signed_turn", "empirical positive/negative probabilities";
    "initialisation", "stratified state-conditional speed ranks and uniform headings";
    "agent_cell_exclusion", "false";
    "acceleration_q90_um_s2", string_of_float e.absolute_acceleration_q90;
    "acceleration_cap_multiplier", string_of_float params.accel_cap_multiplier;
  ]

let run ~rows ~cols ~generations ~seed ~density ~agents ~topology ~plugin_args ~output =
  let parameter_file =
    arg_string "PARAMS" Data.default_parameter_file plugin_args
  in
  let quantile_file =
    arg_string
      "QUANTILES"
      (Data.quantile_file_from_parameter_file parameter_file)
      plugin_args
  in
  let empirical = Data.load_empirical parameter_file quantile_file in
  Data.validate_latent_var1 empirical;
  let params : Model.params = {
    Model.empirical;
    parameter_file;
    quantile_file;
    agents = (match agents with Some n -> n | None -> arg_int "AGENTS" 200 plugin_args);
    init_shape = Model.parse_init_shape (arg_string "INIT" "FULL" plugin_args);
    radius = arg_float "RADIUS" 60.0 plugin_args;
    thickness = arg_float "THICKNESS" 4.0 plugin_args;
    microns_per_cell =
      arg_float
        "MICRONS_PER_CELL"
        empirical.default_microns_per_cell
        plugin_args;
    max_age = arg_int "MAX_AGE" 255 plugin_args;
    accel_cap_multiplier =
      arg_float
        "ACCEL_CAP_MULTIPLIER"
        empirical.default_accel_cap_multiplier
        plugin_args;
    bead_source =
      Model.parse_bead_source
        (arg_string "BEADS" "NONE" plugin_args)
        (arg_string "BEAD_MAP" "" plugin_args)
        (arg_int "BEAD_COUNT" 0 plugin_args);
    bead_radius = arg_float "BEAD_RADIUS" 0.5 plugin_args;
    zoospore_radius = arg_float "ZOOSPORE_RADIUS" 0.5 plugin_args;
    bead_min_gap = arg_float "BEAD_MIN_GAP" 0.0 plugin_args;
    collision_response =
      Model.parse_collision_response
        (arg_string "COLLISION_RESPONSE" "TANGENT" plugin_args);
    collision_slowdown =
      arg_float "COLLISION_SLOWDOWN" 0.5 plugin_args;
    seed;
    topology;
  } in
  if params.microns_per_cell <= 0.0 then
    invalid_arg "Zoospore empirical: MICRONS_PER_CELL must be positive";
  if params.accel_cap_multiplier <= 0.0 then
    invalid_arg "Zoospore empirical beads: ACCEL_CAP_MULTIPLIER must be positive";
  if params.bead_radius <= 0.0 then
    invalid_arg "Zoospore empirical beads: BEAD_RADIUS must be positive";
  if params.zoospore_radius < 0.0 then
    invalid_arg "Zoospore empirical beads: ZOOSPORE_RADIUS must be non-negative";
  if params.bead_min_gap < 0.0 then
    invalid_arg "Zoospore empirical beads: BEAD_MIN_GAP must be non-negative";
  if params.collision_slowdown < 0.0 || params.collision_slowdown > 1.0 then
    invalid_arg
      "Zoospore empirical beads: COLLISION_SLOWDOWN must lie in [0,1]";
  let check_probability name p =
    if p < 0.0 || p > 1.0 then
      invalid_arg
        ("Zoospore empirical: " ^ name ^ " must lie in [0,1]")
  in
  List.iter
    (fun (name, p) -> check_probability name p)
    [
      "P_FAST_to_FAST", empirical.p_fast_fast;
      "P_FAST_to_SLOW", empirical.p_fast_slow;
      "P_SLOW_to_SLOW", empirical.p_slow_slow;
      "P_SLOW_to_FAST", empirical.p_slow_fast;
    ];
  if abs_float (empirical.p_fast_fast +. empirical.p_fast_slow -. 1.0) > 1e-6
     || abs_float (empirical.p_slow_slow +. empirical.p_slow_fast -. 1.0) > 1e-6
  then
    invalid_arg
      "Zoospore empirical: each FAST/SLOW transition-matrix row must sum to 1";
  let grid = Grid.create ~topology ~rows ~cols () in
  let frames, agent_trace = Model.simulate params grid generations in
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
  Abca_io.Binary.save ~filename:output ~archive ~codec:(module Binary_codec)

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
    "Data-driven zoospore model with circular bead obstacles and configurable TANGENT, SLOWDOWN, or BOTH collision response";
  state_count = 3;
  to_color_index;
  run;
  export_xml;
}

let models = [ model ]
