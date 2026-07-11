(*
 * Empirical zoospore plugin for ABCA.
 *
 * Biological movement parameters are loaded from
 * abca_local_parameters.csv. No global trajectory statistic (MSD,
 * straightness, tortuosity or net displacement) is imposed.
 *
 * Distributional assumptions are documented in
 * zoospores_empirical_assumptions.md.
 *)

open Abca

type state = int
(* 0 = empty; 1 = STOP; 2 = RUN *)

type motion_state = Stop | Run

type init_shape =
  | Init_full
  | Init_disk
  | Init_ring

type quantile_dist = {
  probs : float array;
  values : float array;
}

type empirical = {
  dt : float;
  initial_run_fraction : float;
  p_run_run : float;
  p_run_stop : float;
  p_stop_stop : float;
  p_stop_run : float;
  speed_rho : float;
  direction_tau : float;
  speed_turn_rho : float;
  run_speed : quantile_dist;
  stop_speed : quantile_dist;
  abs_turn : quantile_dist;
  signed_acceleration : quantile_dist;
  absolute_acceleration : quantile_dist;
}

type params = {
  empirical : empirical;
  parameter_file : string;
  agents : int;
  init_shape : init_shape;
  radius : float;
  thickness : float;
  microns_per_cell : float;
  max_age : int;
  accel_cap_multiplier : float;
  seed : int;
  topology : Grid.topology;
}

type agent = {
  id : int;
  x : float;
  y : float;
  age : int;
  heading_deg : float;
  speed_um_s : float;
  speed_z : float;
  turn_z : float;
  motion : motion_state;
}

let model_name = "zoospores-empirical"
let default_parameter_file =
  Filename.concat "plugins/zoospores" "abca_local_parameters.csv"

let clamp lo hi x = max lo (min hi x)
let clamp01 x = clamp 0.0 1.0 x

let normalize_degrees angle =
  let a = mod_float angle 360.0 in
  if a < 0.0 then a +. 360.0 else a

let state_of_motion = function Stop -> 1 | Run -> 2
let state_of_agent ag = state_of_motion ag.motion

let row_of_agent ag = int_of_float (Float.floor ag.y)
let col_of_agent ag = int_of_float (Float.floor ag.x)
let coord_of_agent ag = { Grid.row = row_of_agent ag; col = col_of_agent ag }

let find_arg key plugin_args =
  List.assoc_opt (String.uppercase_ascii key) plugin_args

let arg_string key default plugin_args =
  match find_arg key plugin_args with Some x -> x | None -> default

let arg_int key default plugin_args =
  match find_arg key plugin_args with Some x -> int_of_string x | None -> default

let arg_float key default plugin_args =
  match find_arg key plugin_args with Some x -> float_of_string x | None -> default

let parse_init_shape s =
  match String.uppercase_ascii (String.trim s) with
  | "FULL" | "RANDOM" -> Init_full
  | "DISK" | "CIRCLE" -> Init_disk
  | "RING" -> Init_ring
  | other -> failwith ("Zoospore empirical: unknown INIT shape: " ^ other)

let string_of_init_shape = function
  | Init_full -> "full"
  | Init_disk -> "disk"
  | Init_ring -> "ring"

(* Minimal RFC-4180-style CSV line parser. It supports quoted fields and
   doubled quotes; only parameter and value columns are consumed. *)
let parse_csv_line line =
  let fields = ref [] in
  let buffer = Buffer.create 32 in
  let quoted = ref false in
  let i = ref 0 in
  let push () =
    fields := Buffer.contents buffer :: !fields;
    Buffer.clear buffer
  in
  while !i < String.length line do
    let c = line.[!i] in
    if !quoted then begin
      if c = '"' then begin
        if !i + 1 < String.length line && line.[!i + 1] = '"' then begin
          Buffer.add_char buffer '"';
          incr i
        end else
          quoted := false
      end else
        Buffer.add_char buffer c
    end else begin
      match c with
      | '"' -> quoted := true
      | ',' -> push ()
      | _ -> Buffer.add_char buffer c
    end;
    incr i
  done;
  push ();
  List.rev !fields

let read_parameter_table filename =
  let ic = open_in filename in
  Fun.protect
    ~finally:(fun () -> close_in_noerr ic)
    (fun () ->
       let table = Hashtbl.create 128 in
       let first = ref true in
       (try
          while true do
            let line = input_line ic in
            if !first then
              first := false
            else if String.trim line <> "" then
              match parse_csv_line line with
              | _section :: parameter :: value :: _unit :: _ ->
                  Hashtbl.replace table (String.trim parameter) (String.trim value)
              | _ ->
                  failwith ("Zoospore empirical: malformed CSV line: " ^ line)
          done
        with End_of_file -> ());
       table)

let finite_float s =
  let x = float_of_string s in
  match classify_float x with
  | FP_nan | FP_infinite -> None
  | FP_normal | FP_subnormal | FP_zero -> Some x

let required table key =
  match Hashtbl.find_opt table key with
  | None -> failwith ("Zoospore empirical: missing parameter " ^ key)
  | Some s ->
      (match finite_float s with
       | Some x -> x
       | None -> failwith ("Zoospore empirical: non-finite parameter " ^ key))

let optional table key default =
  match Hashtbl.find_opt table key with
  | None -> default
  | Some s -> (match finite_float s with Some x -> x | None -> default)

let make_quantile_dist ~q10 ~q25 ~median ~q75 ~q90 ~nonnegative =
  let lower = q10 -. 1.5 *. (q25 -. q10) in
  let upper = q90 +. 1.5 *. (q90 -. q75) in
  let lower = if nonnegative then max 0.0 lower else lower in
  {
    probs = [| 0.0; 0.10; 0.25; 0.50; 0.75; 0.90; 1.0 |];
    values = [| lower; q10; q25; median; q75; q90; upper |];
  }

let load_empirical filename =
  let t = read_parameter_table filename in
  let speed_dist prefix =
    make_quantile_dist
      ~q10:(required t (prefix ^ "_q10"))
      ~q25:(required t (prefix ^ "_q25"))
      ~median:(required t (prefix ^ "_median"))
      ~q75:(required t (prefix ^ "_q75"))
      ~q90:(required t (prefix ^ "_q90"))
      ~nonnegative:true
  in
  let signed_acceleration =
    make_quantile_dist
      ~q10:(required t "signed_acceleration_q10")
      ~q25:(required t "signed_acceleration_q25")
      ~median:(required t "signed_acceleration_median")
      ~q75:(required t "signed_acceleration_q75")
      ~q90:(required t "signed_acceleration_q90")
      ~nonnegative:false
  in
  let absolute_acceleration =
    make_quantile_dist
      ~q10:(required t "absolute_acceleration_q10")
      ~q25:(required t "absolute_acceleration_q25")
      ~median:(required t "absolute_acceleration_median")
      ~q75:(required t "absolute_acceleration_q75")
      ~q90:(required t "absolute_acceleration_q90")
      ~nonnegative:true
  in
  let abs_turn =
    (* The CSV has no q10 for turning. We infer it from q25 and the origin;
       this is deliberately conservative and is recorded in metadata. *)
    let q25 = required t "absolute_turn_angle_q25" in
    make_quantile_dist
      ~q10:(0.4 *. q25)
      ~q25
      ~median:(required t "absolute_turn_angle_median")
      ~q75:(required t "absolute_turn_angle_q75")
      ~q90:(required t "absolute_turn_angle_q90")
      ~nonnegative:true
  in
  {
    dt = required t "time_step";
    initial_run_fraction = required t "initial_run_fraction";
    p_run_run = required t "P_RUN_to_RUN";
    p_run_stop = required t "P_RUN_to_STOP";
    p_stop_stop = required t "P_STOP_to_STOP";
    p_stop_run = required t "P_STOP_to_RUN";
    speed_rho = required t "speed_lag1_correlation";
    direction_tau = required t "direction_memory_1_over_e_time";
    speed_turn_rho = required t "spearman_speed_vs_abs_turn";
    run_speed = speed_dist "run_speed";
    stop_speed = speed_dist "stop_speed";
    abs_turn;
    signed_acceleration;
    absolute_acceleration;
  }

let interpolate x0 y0 x1 y1 x =
  if x1 = x0 then y0
  else y0 +. (x -. x0) *. (y1 -. y0) /. (x1 -. x0)

let quantile dist u =
  let u = clamp01 u in
  let n = Array.length dist.probs in
  let rec find i =
    if i >= n - 1 then dist.values.(n - 1)
    else if u <= dist.probs.(i + 1) then
      interpolate
        dist.probs.(i) dist.values.(i)
        dist.probs.(i + 1) dist.values.(i + 1)
        u
    else find (i + 1)
  in
  find 0

(* Standard normal CDF approximation. *)
let normal_cdf x =
  let sign = if x < 0.0 then -1.0 else 1.0 in
  let z = abs_float x /. sqrt 2.0 in
  let t = 1.0 /. (1.0 +. 0.3275911 *. z) in
  let a1 = 0.254829592
  and a2 = -0.284496736
  and a3 = 1.421413741
  and a4 = -1.453152027
  and a5 = 1.061405429 in
  let erf =
    sign *. (1.0 -.
      (((((a5 *. t +. a4) *. t +. a3) *. t +. a2) *. t +. a1) *. t)
      *. exp (-. z *. z))
  in
  0.5 *. (1.0 +. erf)

(* Acklam's inverse-normal approximation. *)
let inverse_normal_cdf p =
  let p = clamp 1e-12 (1.0 -. 1e-12) p in
  let a = [|
    -3.969683028665376e+01; 2.209460984245205e+02;
    -2.759285104469687e+02; 1.383577518672690e+02;
    -3.066479806614716e+01; 2.506628277459239e+00
  |] in
  let b = [|
    -5.447609879822406e+01; 1.615858368580409e+02;
    -1.556989798598866e+02; 6.680131188771972e+01;
    -1.328068155288572e+01
  |] in
  let c = [|
    -7.784894002430293e-03; -3.223964580411365e-01;
    -2.400758277161838e+00; -2.549732539343734e+00;
    4.374664141464968e+00; 2.938163982698783e+00
  |] in
  let d = [|
    7.784695709041462e-03; 3.224671290700398e-01;
    2.445134137142996e+00; 3.754408661907416e+00
  |] in
  let plow = 0.02425 in
  let phigh = 1.0 -. plow in
  if p < plow then begin
    let q = sqrt (-2.0 *. log p) in
    (((((c.(0) *. q +. c.(1)) *. q +. c.(2)) *. q +. c.(3)) *. q +. c.(4)) *. q +. c.(5)) /.
    ((((d.(0) *. q +. d.(1)) *. q +. d.(2)) *. q +. d.(3)) *. q +. 1.0)
  end else if p > phigh then begin
    let q = sqrt (-2.0 *. log (1.0 -. p)) in
    -.(((((c.(0) *. q +. c.(1)) *. q +. c.(2)) *. q +. c.(3)) *. q +. c.(4)) *. q +. c.(5)) /.
    ((((d.(0) *. q +. d.(1)) *. q +. d.(2)) *. q +. d.(3)) *. q +. 1.0)
  end else begin
    let q = p -. 0.5 in
    let r = q *. q in
    (((((a.(0) *. r +. a.(1)) *. r +. a.(2)) *. r +. a.(3)) *. r +. a.(4)) *. r +. a.(5)) *. q /.
    (((((b.(0) *. r +. b.(1)) *. r +. b.(2)) *. r +. b.(3)) *. r +. b.(4)) *. r +. 1.0)
  end

let standard_normal rng =
  (* Box-Muller; the lower bound prevents log 0. *)
  let u1 = max 1e-12 (Rng.float rng 1.0) in
  let u2 = Rng.float rng 1.0 in
  sqrt (-2.0 *. log u1) *. cos (2.0 *. Float.pi *. u2)

let distribution_for_state empirical = function
  | Run -> empirical.run_speed
  | Stop -> empirical.stop_speed

let transition_state rng empirical = function
  | Run -> if Rng.chance rng empirical.p_run_stop then Stop else Run
  | Stop -> if Rng.chance rng empirical.p_stop_run then Run else Stop

let geometry_of_params params =
  match params.init_shape with
  | Init_full -> Initial_geometry.Full_grid
  | Init_disk -> Initial_geometry.Disk { center = None; radius = params.radius }
  | Init_ring ->
      Initial_geometry.Ring {
        center = None;
        radius = params.radius;
        thickness = params.thickness;
      }

let initial_agents params grid =
  let rng = Rng.create params.seed in
  let coords =
    Initial_geometry.select grid (geometry_of_params params)
    |> Initial_geometry.random_subset rng ~n:params.agents
  in
  let n = Array.length coords in
  let latent = Array.init n (fun i ->
      inverse_normal_cdf ((float_of_int i +. 0.5) /. float_of_int n)) in
  let headings = Array.init n (fun i ->
      360.0 *. (float_of_int i +. 0.5) /. float_of_int n) in
  let motions = Array.init n (fun i ->
      if float_of_int i < params.empirical.initial_run_fraction *. float_of_int n
      then Run else Stop) in
  Rng.shuffle_array rng latent;
  Rng.shuffle_array rng headings;
  Rng.shuffle_array rng motions;
  Array.mapi
    (fun id coord ->
       let motion = motions.(id) in
       let speed_z = latent.(id) in
       let speed_um_s =
         quantile (distribution_for_state params.empirical motion)
           (normal_cdf speed_z)
       in
       {
         id;
         x = float_of_int coord.Grid.col +. 0.5;
         y = float_of_int coord.Grid.row +. 0.5;
         age = 1;
         heading_deg = headings.(id);
         speed_um_s;
         speed_z;
         turn_z = standard_normal rng;
         motion;
       })
    coords

let max_acceleration empirical multiplier =
  multiplier *. quantile empirical.absolute_acceleration 0.90

let update_speed rng params ag next_motion =
  let e = params.empirical in
  let rho = clamp (-0.999) 0.999 e.speed_rho in
  let z = rho *. ag.speed_z +. sqrt (1.0 -. rho *. rho) *. standard_normal rng in
  let target =
    quantile (distribution_for_state e next_motion) (normal_cdf z)
  in
  (* The empirical speed marginals and lag-1 correlation drive the update.
     Acceleration summaries are used only as a generous winsorisation guard
     against unbounded extrapolation from summary quantiles. *)
  let max_dv = max_acceleration e params.accel_cap_multiplier *. e.dt in
  let dv = clamp (-.max_dv) max_dv (target -. ag.speed_um_s) in
  max 0.0 (ag.speed_um_s +. dv), z

let update_turn rng params speed_z previous_turn_z =
  let e = params.empirical in
  let rho_direction =
    if e.direction_tau <= 0.0 then 0.0
    else exp (-. e.dt /. e.direction_tau)
  in
  let rho_coupling = clamp (-0.95) 0.95 e.speed_turn_rho in
  let noise = standard_normal rng in
  let coupled_noise =
    rho_coupling *. speed_z +.
    sqrt (1.0 -. rho_coupling *. rho_coupling) *. noise
  in
  let turn_z =
    rho_direction *. previous_turn_z +.
    sqrt (1.0 -. rho_direction *. rho_direction) *. coupled_noise
  in
  let magnitude = quantile e.abs_turn (normal_cdf turn_z) in
  (* The observed signed median is close to zero and no handedness parameter
     was estimated; signs are therefore symmetric. *)
  let signed = if Rng.bool rng then magnitude else -.magnitude in
  signed, turn_z

let wrap_coordinate size x =
  let s = float_of_int size in
  let y = mod_float x s in
  if y < 0.0 then y +. s else y

let reflected_heading rows cols x y heading =
  let h = ref heading in
  if x < 0.0 || x >= float_of_int cols then h := 180.0 -. !h;
  if y < 0.0 || y >= float_of_int rows then h := -. !h;
  normalize_degrees !h

let move_agent params grid ag heading speed =
  let distance_cells = speed *. params.empirical.dt /. params.microns_per_cell in
  let theta = heading *. Float.pi /. 180.0 in
  let x1 = ag.x +. distance_cells *. cos theta in
  let y1 = ag.y +. distance_cells *. sin theta in
  match params.topology with
  | Grid.Toroidal ->
      wrap_coordinate (Grid.cols grid) x1,
      wrap_coordinate (Grid.rows grid) y1,
      heading
  | Grid.Bounded ->
      if x1 >= 0.0 && x1 < float_of_int (Grid.cols grid)
         && y1 >= 0.0 && y1 < float_of_int (Grid.rows grid)
      then x1, y1, heading
      else
        let reflected =
          reflected_heading (Grid.rows grid) (Grid.cols grid) x1 y1 heading
        in
        let theta2 = reflected *. Float.pi /. 180.0 in
        let x2 = ag.x +. distance_cells *. cos theta2 in
        let y2 = ag.y +. distance_cells *. sin theta2 in
        clamp 0.0 (float_of_int (Grid.cols grid) -. 1e-9) x2,
        clamp 0.0 (float_of_int (Grid.rows grid) -. 1e-9) y2,
        reflected

let step_agent rng params grid ag =
  let next_motion = transition_state rng params.empirical ag.motion in
  let speed_um_s, speed_z = update_speed rng params ag next_motion in
  let delta_heading, turn_z = update_turn rng params speed_z ag.turn_z in
  let proposed_heading = normalize_degrees (ag.heading_deg +. delta_heading) in
  let x, y, heading_deg = move_agent params grid ag proposed_heading speed_um_s in
  {
    ag with
    x;
    y;
    age = min params.max_age (ag.age + 1);
    heading_deg;
    speed_um_s;
    speed_z;
    turn_z;
    motion = next_motion;
  }

let step_agents rng params grid agents =
  (* Agents are physically continuous. Sharing a display cell is therefore
     not treated as a collision; no interaction law was measured. *)
  Array.map (step_agent rng params grid) agents

let empty_frame grid =
  Array.init (Grid.rows grid) (fun _ -> Array.make (Grid.cols grid) 0)

let frame_of_agents grid agents =
  let frame = empty_frame grid in
  Array.iter
    (fun ag ->
       let coord = coord_of_agent ag in
       if Grid.valid grid coord then
         frame.(coord.Grid.row).(coord.col) <- state_of_agent ag)
    agents;
  frame

let trace_record frame ag : Abca_io.Agent_trace.record =
  {
    frame;
    id = ag.id;
    x = ag.x;
    y = ag.y;
    row = row_of_agent ag;
    col = col_of_agent ag;
    angle = int_of_float (Float.round (normalize_degrees ag.heading_deg)) mod 360;
    age = ag.age;
    state = state_of_agent ag;
  }

let simulate params grid generations =
  let rng = Rng.create params.seed in
  let frames = Array.make (generations + 1) [||] in
  let trace = ref [] in
  let agents = ref (initial_agents params grid) in
  let record generation =
    Array.iter
      (fun ag -> trace := trace_record generation ag :: !trace)
      !agents
  in
  frames.(0) <- frame_of_agents grid !agents;
  record 0;
  for generation = 1 to generations do
    agents := step_agents rng params grid !agents;
    frames.(generation) <- frame_of_agents grid !agents;
    record generation
  done;
  frames, Array.of_list (List.rev !trace)

module Binary_codec = struct
  type t = state
  let to_int32 x = Int32.of_int x
  let of_int32 x = Int32.to_int x
end

module Xml_codec = struct
  type t = state
  let to_string = string_of_int
end

let to_color_index x = x

let metadata params ~rows ~cols ~generations ~density =
  let e = params.empirical in
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
    "time_step_s", string_of_float e.dt;
    "microns_per_cell", string_of_float params.microns_per_cell;
    "init", string_of_init_shape params.init_shape;
    "radius", string_of_float params.radius;
    "thickness", string_of_float params.thickness;
    "distribution_speed", "piecewise-linear inverse empirical quantiles";
    "dependence_speed", "Gaussian copula AR(1)";
    "distribution_turn", "piecewise-linear inverse empirical absolute-turn quantiles";
    "dependence_turn", "Gaussian copula with directional memory and speed coupling";
    "signed_turn", "symmetric Bernoulli sign";
    "agent_cell_exclusion", "false";
    "acceleration_guard", "3x empirical q90 by default";
  ]

let run ~rows ~cols ~generations ~seed ~density ~agents ~topology ~plugin_args ~output =
  let parameter_file =
    arg_string "PARAMS" default_parameter_file plugin_args
  in
  let empirical = load_empirical parameter_file in
  let params = {
    empirical;
    parameter_file;
    agents = (match agents with Some n -> n | None -> arg_int "AGENTS" 200 plugin_args);
    init_shape = parse_init_shape (arg_string "INIT" "FULL" plugin_args);
    radius = arg_float "RADIUS" 60.0 plugin_args;
    thickness = arg_float "THICKNESS" 4.0 plugin_args;
    microns_per_cell = arg_float "MICRONS_PER_CELL" 10.0 plugin_args;
    max_age = arg_int "MAX_AGE" 255 plugin_args;
    accel_cap_multiplier = arg_float "ACCEL_CAP_MULTIPLIER" 3.0 plugin_args;
    seed;
    topology;
  } in
  if params.microns_per_cell <= 0.0 then
    invalid_arg "Zoospore empirical: MICRONS_PER_CELL must be positive";
  let grid = Grid.create ~topology ~rows ~cols () in
  let frames, agent_trace = simulate params grid generations in
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
    "Data-driven zoospore model using local RUN/STOP, speed and steering statistics";
  state_count = 3;
  to_color_index;
  run;
  export_xml;
}

let models = [ model ]
