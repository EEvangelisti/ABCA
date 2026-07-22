(* Hidden-Markov zoospore plugin for ABCA.
 *
 * The plugin reads three TSV files exported by
 * fit_and_interpret_zoospore_hmm.py:
 *
 *   - hmm_transition_matrix.tsv
 *   - hmm_start_probabilities.tsv
 *   - hmm_state_quantiles.tsv
 *
 * Each agent carries one hidden locomotor state. At every generation:
 *
 *   1. the next hidden state is sampled from the corresponding row of the
 *      fitted HMM transition matrix;
 *   2. a speed and an absolute turn angle are sampled from the empirical
 *      state-conditional quantile tables;
 *   3. the sign of the turn is sampled from the state-specific empirical
 *      probability of a positive turn;
 *   4. heading and continuous position are updated.
 *
 * The HMM states are statistical locomotor regimes. They are deliberately not
 * renamed or interpreted inside the simulation code.
 *)

open Abca

type state = int
(* 0 = empty; HMM state k is displayed as cellular state k + 1. *)

type init_shape =
  | Init_full
  | Init_disk
  | Init_ring

type quantile_dist = {
  probs : float array;
  values : float array;
}

type hmm_state_distribution = {
  speed : quantile_dist;
  abs_turn : quantile_dist;
  positive_turn_probability : float;
  n_observations : int;
}

type hmm_model = {
  n_states : int;
  start_probabilities : float array;
  transition_matrix : float array array;
  state_distributions : hmm_state_distribution array;
}

type params = {
  hmm : hmm_model;
  transition_file : string;
  start_file : string;
  quantile_file : string;
  agents : int;
  init_shape : init_shape;
  radius : float;
  thickness : float;
  microns_per_cell : float;
  dt : float;
  max_age : int;
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
  hmm_state : int;
}

let model_name = "zoospores-hmm"

let default_hmm_dir =
  Filename.concat "plugins/zoospores" "hmm_analysis"

let default_transition_file =
  Filename.concat default_hmm_dir "hmm_transition_matrix.tsv"

let default_start_file =
  Filename.concat default_hmm_dir "hmm_start_probabilities.tsv"

let default_quantile_file =
  Filename.concat default_hmm_dir "hmm_state_quantiles.tsv"

let clamp lo hi x = max lo (min hi x)
let clamp01 x = clamp 0.0 1.0 x

let normalize_degrees angle =
  let a = mod_float angle 360.0 in
  if a < 0.0 then a +. 360.0 else a

let row_of_agent ag = int_of_float (Float.floor ag.y)
let col_of_agent ag = int_of_float (Float.floor ag.x)

let coord_of_agent ag =
  { Grid.row = row_of_agent ag; col = col_of_agent ag }

let state_of_agent ag = ag.hmm_state + 1

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

let parse_init_shape s =
  match String.uppercase_ascii (String.trim s) with
  | "FULL" | "RANDOM" -> Init_full
  | "DISK" | "CIRCLE" -> Init_disk
  | "RING" -> Init_ring
  | other -> failwith ("Zoospore HMM: unknown INIT shape: " ^ other)

let string_of_init_shape = function
  | Init_full -> "full"
  | Init_disk -> "disk"
  | Init_ring -> "ring"

(* RFC-4180-style parser generalized to an arbitrary one-character separator.
   It supports quoted fields and doubled quotes. *)
let parse_delimited_line separator line =
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
      if c = '"' then
        quoted := true
      else if c = separator then
        push ()
      else
        Buffer.add_char buffer c
    end;
    incr i
  done;
  push ();
  List.rev !fields

let separator_of_filename filename =
  if Filename.check_suffix (String.lowercase_ascii filename) ".csv"
  then ','
  else '\t'

let read_table filename =
  let separator = separator_of_filename filename in
  let ic = open_in filename in
  Fun.protect
    ~finally:(fun () -> close_in_noerr ic)
    (fun () ->
       let header =
         try
           input_line ic
           |> parse_delimited_line separator
           |> List.map String.trim
           |> Array.of_list
         with End_of_file ->
           failwith ("Zoospore HMM: empty table: " ^ filename)
       in
       let rows = ref [] in
       (try
          while true do
            let line = input_line ic in
            if String.trim line <> "" then begin
              let fields =
                parse_delimited_line separator line
                |> List.map String.trim
                |> Array.of_list
              in
              if Array.length fields <> Array.length header then
                failwith
                  (Printf.sprintf
                     "Zoospore HMM: malformed row in %s: expected %d fields, got %d"
                     filename
                     (Array.length header)
                     (Array.length fields));
              rows := fields :: !rows
            end
          done
        with End_of_file -> ());
       header, Array.of_list (List.rev !rows))

let column_index header name =
  let rec find i =
    if i >= Array.length header then
      failwith ("Zoospore HMM: missing column " ^ name)
    else if header.(i) = name then
      i
    else
      find (i + 1)
  in
  find 0

let finite_float context s =
  let x =
    try float_of_string s
    with Failure _ ->
      failwith ("Zoospore HMM: invalid float for " ^ context ^ ": " ^ s)
  in
  match classify_float x with
  | FP_nan | FP_infinite ->
      failwith ("Zoospore HMM: non-finite float for " ^ context)
  | FP_normal | FP_subnormal | FP_zero -> x

let integer context s =
  try int_of_string s
  with Failure _ ->
    try int_of_float (float_of_string s)
    with Failure _ ->
      failwith ("Zoospore HMM: invalid integer for " ^ context ^ ": " ^ s)

let validate_probability context p =
  if p < 0.0 || p > 1.0 then
    invalid_arg
      (Printf.sprintf
         "Zoospore HMM: %s must lie in [0,1], got %.17g"
         context p)

let validate_probability_vector context values =
  if Array.length values = 0 then
    invalid_arg ("Zoospore HMM: empty probability vector for " ^ context);
  Array.iteri
    (fun i p ->
       validate_probability
         (Printf.sprintf "%s[%d]" context i)
         p)
    values;
  let total = Array.fold_left ( +. ) 0.0 values in
  if abs_float (total -. 1.0) > 1e-6 then
    invalid_arg
      (Printf.sprintf
         "Zoospore HMM: probabilities for %s sum to %.17g instead of 1"
         context total)

let read_transition_matrix filename =
  let header, rows = read_table filename in
  let from_col = column_index header "from_state" in
  let n_states = Array.length header - 1 in
  if n_states < 2 then
    failwith "Zoospore HMM: transition matrix must contain at least two states";
  let to_cols =
    Array.init n_states (fun state ->
        column_index header (Printf.sprintf "to_state_%d" state))
  in
  if Array.length rows <> n_states then
    failwith
      (Printf.sprintf
         "Zoospore HMM: transition matrix has %d rows for %d states"
         (Array.length rows) n_states);
  let matrix = Array.make_matrix n_states n_states nan in
  Array.iter
    (fun row ->
       let from_state = integer "from_state" row.(from_col) in
       if from_state < 0 || from_state >= n_states then
         failwith
           (Printf.sprintf
              "Zoospore HMM: invalid transition source state %d"
              from_state);
       if classify_float matrix.(from_state).(0) <> FP_nan then
         failwith
           (Printf.sprintf
              "Zoospore HMM: duplicate transition row for state %d"
              from_state);
       Array.iteri
         (fun target col ->
            matrix.(from_state).(target) <-
              finite_float
                (Printf.sprintf "transition %d -> %d" from_state target)
                row.(col))
         to_cols)
    rows;
  Array.iteri
    (fun state probabilities ->
       if Array.exists (fun x -> classify_float x = FP_nan) probabilities then
         failwith
           (Printf.sprintf
              "Zoospore HMM: missing transition row for state %d"
              state);
       validate_probability_vector
         (Printf.sprintf "transition row %d" state)
         probabilities)
    matrix;
  matrix

let read_start_probabilities filename n_states =
  let header, rows = read_table filename in
  let state_col = column_index header "state" in
  let probability_col = column_index header "start_probability" in
  let probabilities = Array.make n_states nan in
  Array.iter
    (fun row ->
       let state = integer "state" row.(state_col) in
       if state < 0 || state >= n_states then
         failwith
           (Printf.sprintf
              "Zoospore HMM: invalid initial state %d"
              state);
       if classify_float probabilities.(state) <> FP_nan then
         failwith
           (Printf.sprintf
              "Zoospore HMM: duplicate initial probability for state %d"
              state);
       probabilities.(state) <-
         finite_float "start_probability" row.(probability_col))
    rows;
  if Array.exists (fun x -> classify_float x = FP_nan) probabilities then
    failwith
      "Zoospore HMM: one or more initial-state probabilities are missing";
  validate_probability_vector "initial states" probabilities;
  probabilities

let quantile_of_pairs context pairs =
  let pairs =
    List.sort (fun (p1, _) (p2, _) -> compare p1 p2) pairs
  in
  if List.length pairs < 2 then
    failwith
      ("Zoospore HMM: fewer than two quantiles for " ^ context);
  let probs = Array.of_list (List.map fst pairs) in
  let values = Array.of_list (List.map snd pairs) in
  Array.iteri
    (fun i p ->
       validate_probability
         (Printf.sprintf "%s probability[%d]" context i)
         p;
       if i > 0 && p <= probs.(i - 1) then
         failwith
           ("Zoospore HMM: quantile probabilities must be strictly increasing for "
            ^ context))
    probs;
  { probs; values }

let read_state_quantiles filename n_states =
  let header, rows = read_table filename in
  let state_col = column_index header "state" in
  let probability_col = column_index header "probability" in
  let speed_col =
    let rec find i =
      if i >= Array.length header then
        failwith "Zoospore HMM: no speed_*_per_s column in quantile table"
      else
        let name = header.(i) in
        if String.length name >= 6
           && String.sub name 0 6 = "speed_"
           && (Filename.check_suffix name "_per_s"
               || Filename.check_suffix name "/s")
        then i
        else find (i + 1)
    in
    find 0
  in
  let turn_col = column_index header "abs_turn_angle_deg" in
  let positive_col = column_index header "positive_turn_probability" in
  let count_col = column_index header "n_observations" in

  let speed_pairs = Array.make n_states [] in
  let turn_pairs = Array.make n_states [] in
  let positive_turn = Array.make n_states nan in
  let observation_counts = Array.make n_states (-1) in

  Array.iter
    (fun row ->
       let state = integer "state" row.(state_col) in
       if state < 0 || state >= n_states then
         failwith
           (Printf.sprintf "Zoospore HMM: invalid quantile state %d" state);
       let probability =
         finite_float "quantile probability" row.(probability_col)
       in
       let speed =
         finite_float "state speed quantile" row.(speed_col)
       in
       let turn =
         finite_float "state turn quantile" row.(turn_col)
       in
       let p_positive =
         finite_float "positive_turn_probability" row.(positive_col)
       in
       let n_observations =
         integer "n_observations" row.(count_col)
       in
       validate_probability "positive_turn_probability" p_positive;
       speed_pairs.(state) <- (probability, speed) :: speed_pairs.(state);
       turn_pairs.(state) <- (probability, turn) :: turn_pairs.(state);
       if classify_float positive_turn.(state) = FP_nan then
         positive_turn.(state) <- p_positive
       else if abs_float (positive_turn.(state) -. p_positive) > 1e-12 then
         failwith
           (Printf.sprintf
              "Zoospore HMM: inconsistent positive-turn probability for state %d"
              state);
       if observation_counts.(state) < 0 then
         observation_counts.(state) <- n_observations
       else if observation_counts.(state) <> n_observations then
         failwith
           (Printf.sprintf
              "Zoospore HMM: inconsistent observation count for state %d"
              state))
    rows;

  Array.init n_states (fun state ->
      if classify_float positive_turn.(state) = FP_nan then
        failwith
          (Printf.sprintf
             "Zoospore HMM: no quantiles found for state %d"
             state);
      {
        speed =
          quantile_of_pairs
            (Printf.sprintf "state %d speed" state)
            speed_pairs.(state);
        abs_turn =
          quantile_of_pairs
            (Printf.sprintf "state %d absolute turn" state)
            turn_pairs.(state);
        positive_turn_probability = positive_turn.(state);
        n_observations = observation_counts.(state);
      })

let load_hmm ~transition_file ~start_file ~quantile_file =
  let transition_matrix = read_transition_matrix transition_file in
  let n_states = Array.length transition_matrix in
  let start_probabilities =
    read_start_probabilities start_file n_states
  in
  let state_distributions =
    read_state_quantiles quantile_file n_states
  in
  {
    n_states;
    start_probabilities;
    transition_matrix;
    state_distributions;
  }

let interpolate x0 y0 x1 y1 x =
  if x1 = x0 then y0
  else y0 +. (x -. x0) *. (y1 -. y0) /. (x1 -. x0)

let quantile dist u =
  let u = clamp01 u in
  let n = Array.length dist.probs in
  if u <= dist.probs.(0) then
    dist.values.(0)
  else if u >= dist.probs.(n - 1) then
    dist.values.(n - 1)
  else begin
    let rec find i =
      if u <= dist.probs.(i + 1) then
        interpolate
          dist.probs.(i) dist.values.(i)
          dist.probs.(i + 1) dist.values.(i + 1)
          u
      else
        find (i + 1)
    in
    find 0
  end

let sample_categorical rng probabilities =
  let u = Rng.float rng 1.0 in
  let cumulative = ref 0.0 in
  let selected = ref (Array.length probabilities - 1) in
  let found = ref false in
  let i = ref 0 in
  while not !found && !i < Array.length probabilities do
    cumulative := !cumulative +. probabilities.(!i);
    if u <= !cumulative then begin
      selected := !i;
      found := true
    end;
    incr i
  done;
  !selected

let stratified_uniforms rng n =
  if n <= 0 then [||]
  else begin
    let nf = float_of_int n in
    let values =
      Array.init n (fun i ->
          (float_of_int i +. 0.5) /. nf)
    in
    Rng.shuffle_array rng values;
    values
  end

let stratified_categorical rng n probabilities =
  let cumulative = Array.copy probabilities in
  for i = 1 to Array.length cumulative - 1 do
    cumulative.(i) <- cumulative.(i) +. cumulative.(i - 1)
  done;
  let uniforms = stratified_uniforms rng n in
  Array.map
    (fun u ->
       let rec find state =
         if state >= Array.length cumulative - 1
            || u <= cumulative.(state)
         then state
         else find (state + 1)
       in
       find 0)
    uniforms

let geometry_of_params params =
  match params.init_shape with
  | Init_full ->
      Initial_geometry.Full_grid
  | Init_disk ->
      Initial_geometry.Disk {
        center = None;
        radius = params.radius;
      }
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
  let states =
    stratified_categorical
      rng n params.hmm.start_probabilities
  in
  let headings =
    stratified_uniforms rng n
    |> Array.map (fun u -> 360.0 *. u)
  in

  (* Stratify the initial speed ranks independently within every HMM state. *)
  let counts = Array.make params.hmm.n_states 0 in
  Array.iter (fun state -> counts.(state) <- counts.(state) + 1) states;
  let speed_uniforms =
    Array.init params.hmm.n_states
      (fun state -> stratified_uniforms rng counts.(state))
  in
  let speed_indices = Array.make params.hmm.n_states 0 in

  Array.mapi
    (fun id coord ->
       let hmm_state = states.(id) in
       let index = speed_indices.(hmm_state) in
       speed_indices.(hmm_state) <- index + 1;
       let distribution =
         params.hmm.state_distributions.(hmm_state)
       in
       let speed_um_s =
         quantile distribution.speed speed_uniforms.(hmm_state).(index)
       in
       {
         id;
         x = float_of_int coord.Grid.col +. 0.5;
         y = float_of_int coord.Grid.row +. 0.5;
         age = 1;
         heading_deg = headings.(id);
         speed_um_s;
         hmm_state;
       })
    coords

let turn_sign rng probability_positive =
  if Rng.chance rng probability_positive then 1.0 else -1.0

let wrap_coordinate size x =
  let s = float_of_int size in
  let y = mod_float x s in
  if y < 0.0 then y +. s else y

let reflected_heading rows cols x y heading =
  let h = ref heading in
  if x < 0.0 || x >= float_of_int cols then
    h := 180.0 -. !h;
  if y < 0.0 || y >= float_of_int rows then
    h := -. !h;
  normalize_degrees !h

let move_agent params grid ag heading speed =
  let distance_cells =
    speed *. params.dt /. params.microns_per_cell
  in
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
      then
        x1, y1, heading
      else begin
        let reflected =
          reflected_heading
            (Grid.rows grid)
            (Grid.cols grid)
            x1 y1 heading
        in
        let theta2 = reflected *. Float.pi /. 180.0 in
        let x2 = ag.x +. distance_cells *. cos theta2 in
        let y2 = ag.y +. distance_cells *. sin theta2 in
        clamp 0.0 (float_of_int (Grid.cols grid) -. 1e-9) x2,
        clamp 0.0 (float_of_int (Grid.rows grid) -. 1e-9) y2,
        reflected
      end

let step_agent rng params grid ag =
  let next_state =
    sample_categorical
      rng params.hmm.transition_matrix.(ag.hmm_state)
  in
  let distribution =
    params.hmm.state_distributions.(next_state)
  in

  (* Speed and turn magnitude are conditionally sampled from the decoded
     empirical observations assigned to the newly entered HMM state. *)
  let speed_um_s =
    quantile distribution.speed (Rng.float rng 1.0)
  in
  let turn_magnitude =
    quantile distribution.abs_turn (Rng.float rng 1.0)
  in
  let delta_heading =
    turn_sign rng distribution.positive_turn_probability
    *. turn_magnitude
  in
  let proposed_heading =
    normalize_degrees (ag.heading_deg +. delta_heading)
  in
  let x, y, heading_deg =
    move_agent params grid ag proposed_heading speed_um_s
  in
  {
    ag with
    x;
    y;
    age = min params.max_age (ag.age + 1);
    heading_deg;
    speed_um_s;
    hmm_state = next_state;
  }

let step_agents rng params grid agents =
  Array.map (step_agent rng params grid) agents

let empty_frame grid =
  Array.init
    (Grid.rows grid)
    (fun _ -> Array.make (Grid.cols grid) 0)

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
    angle =
      int_of_float
        (Float.round (normalize_degrees ag.heading_deg))
      mod 360;
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
      (fun ag ->
         trace := trace_record generation ag :: !trace)
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

let to_color_index = function
  | 0 -> None
  | s -> Some (min s 255)

let metadata params ~rows ~cols ~generations ~density =
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
    "topology",
      (match params.topology with
       | Grid.Bounded -> "bounded"
       | Grid.Toroidal -> "toroidal");
    "transition_file", params.transition_file;
    "start_file", params.start_file;
    "quantile_file", params.quantile_file;
    "hmm_states", string_of_int params.hmm.n_states;
    "time_step_s", string_of_float params.dt;
    "microns_per_cell", string_of_float params.microns_per_cell;
    "init", string_of_init_shape params.init_shape;
    "radius", string_of_float params.radius;
    "thickness", string_of_float params.thickness;
    "state_dynamics", "fitted HMM transition matrix";
    "speed_distribution", "state-conditional empirical inverse CDF";
    "turn_distribution", "state-conditional empirical inverse CDF";
    "signed_turn", "state-specific empirical positive-turn probability";
    "acceleration", "derived from consecutive sampled speeds";
    "agent_cell_exclusion", "false";
  ]

let run
    ~rows
    ~cols
    ~generations
    ~seed
    ~density
    ~agents
    ~topology
    ~plugin_args
    ~output =
  let transition_file =
    arg_string
      "TRANSITIONS"
      default_transition_file
      plugin_args
  in
  let start_file =
    arg_string
      "START_PROBABILITIES"
      default_start_file
      plugin_args
  in
  let quantile_file =
    arg_string
      "STATE_QUANTILES"
      default_quantile_file
      plugin_args
  in
  let hmm =
    load_hmm
      ~transition_file
      ~start_file
      ~quantile_file
  in
  let params = {
    hmm;
    transition_file;
    start_file;
    quantile_file;
    agents =
      (match agents with
       | Some n -> n
       | None -> arg_int "AGENTS" 200 plugin_args);
    init_shape =
      parse_init_shape
        (arg_string "INIT" "FULL" plugin_args);
    radius = arg_float "RADIUS" 60.0 plugin_args;
    thickness = arg_float "THICKNESS" 4.0 plugin_args;
    microns_per_cell =
      arg_float "MICRONS_PER_CELL" 10.0 plugin_args;
    dt = arg_float "DT" 0.22 plugin_args;
    max_age = arg_int "MAX_AGE" 255 plugin_args;
    seed;
    topology;
  } in
  if params.agents < 0 then
    invalid_arg "Zoospore HMM: AGENTS must be non-negative";
  if params.microns_per_cell <= 0.0 then
    invalid_arg "Zoospore HMM: MICRONS_PER_CELL must be positive";
  if params.dt <= 0.0 then
    invalid_arg "Zoospore HMM: DT must be positive";
  if params.max_age < 1 then
    invalid_arg "Zoospore HMM: MAX_AGE must be at least 1";

  let grid = Grid.create ~topology ~rows ~cols () in
  let frames, agent_trace =
    simulate params grid generations
  in
  let archive =
    Abca_io.Binary.make_archive
      ~rows
      ~cols
      ~generation:generations
      ~metadata:
        (metadata
           params
           ~rows
           ~cols
           ~generations
           ~density)
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
    "Data-driven zoospore model using hidden Markov locomotor states";
  state_count = 8;
  to_color_index;
  run;
  export_xml;
}

let models = [ model ]
