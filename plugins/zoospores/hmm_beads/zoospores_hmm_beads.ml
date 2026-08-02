(* Hidden-Markov zoospore plugin for ABCA.
 *
 * The plugin reads three TSV files exported by
 * fit_and_interpret_zoospore_hmm.py:
 *
 *   - hmm_transition_matrix.tsv
 *   - hmm_start_probabilities.tsv
 *   - hmm_state_quantiles.tsv
 *
 * Each agent carries the hidden state that will emit the next movement.
 * At every generation, the simulation follows the standard HMM order:
 *
 *   1. an observation (speed and turning angle) is emitted conditionally on
 *      the current hidden state;
 *   2. heading and continuous position are updated from that observation;
 *   3. the next hidden state is sampled from the corresponding row of the
 *      fitted HMM transition matrix.
 *
 * Thus the initial-state distribution is used for the first emitted movement,
 * and every movement is associated with the state that generated it.
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

type bead_source =
  | No_beads
  | Beads_from_file of string
  | Random_beads of int

type collision_response =
  | Tangential
  | Slowdown
  | Both

type bead = {
  bx : float;
  by : float;
  radius : float;
}

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
  slow_state : int;
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
  bead_source : bead_source;
  bead_radius : float;
  zoospore_radius : float;
  bead_min_gap : float;
  collision_response : collision_response;
  collision_slowdown : float;
  collision_speed_factor : float;
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
  (* State that will emit the next movement. *)
  hmm_state : int;
  (* State that emitted the movement ending at the current frame. *)
  emitted_state : int;
}

let model_name = "zoospores-hmm-beads"

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

let state_of_agent ag = ag.emitted_state + 1

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

let parse_bead_source mode filename count =
  match String.uppercase_ascii (String.trim mode) with
  | "NONE" | "NO" | "OFF" -> No_beads
  | "FILE" | "MAP" ->
      if String.trim filename = "" then
        invalid_arg "Zoospore HMM beads: BEAD_MAP is required when BEADS=FILE";
      Beads_from_file filename
  | "RANDOM" ->
      if count < 0 then
        invalid_arg "Zoospore HMM beads: BEAD_COUNT must be non-negative";
      Random_beads count
  | other ->
      failwith ("Zoospore HMM beads: unknown BEADS mode: " ^ other)

let string_of_bead_source = function
  | No_beads -> "none"
  | Beads_from_file filename -> "file:" ^ filename
  | Random_beads n -> "random:" ^ string_of_int n

let parse_collision_response s =
  match String.uppercase_ascii (String.trim s) with
  | "TANGENT" | "TANGENTIAL" | "SLIDE" -> Tangential
  | "SLOWDOWN" | "SLOW" | "STOP" -> Slowdown
  | "BOTH" | "TANGENT_SLOWDOWN" | "SLOWDOWN_TANGENT" -> Both
  | other ->
      failwith
        ("Zoospore HMM beads: unknown COLLISION_RESPONSE: " ^ other)

let string_of_collision_response = function
  | Tangential -> "tangential"
  | Slowdown -> "slowdown"
  | Both -> "both"

let split_csv line =
  String.split_on_char ',' line |> List.map String.trim

let load_beads filename default_radius =
  let ic = open_in filename in
  Fun.protect
    ~finally:(fun () -> close_in_noerr ic)
    (fun () ->
       let beads = ref [] in
       let line_number = ref 0 in
       (try
          while true do
            incr line_number;
            let line = String.trim (input_line ic) in
            if line <> "" && line.[0] <> '#' then
              match split_csv line with
              | x :: y :: radius :: _ ->
                  (try
                     beads := {
                       bx = float_of_string x;
                       by = float_of_string y;
                       radius = float_of_string radius;
                     } :: !beads
                   with Failure _ when !line_number = 1 -> ())
              | x :: y :: _ ->
                  (try
                     beads := {
                       bx = float_of_string x;
                       by = float_of_string y;
                       radius = default_radius;
                     } :: !beads
                   with Failure _ when !line_number = 1 -> ())
              | _ ->
                  failwith
                    (Printf.sprintf
                       "Zoospore HMM beads: malformed bead-map line %d"
                       !line_number)
          done
        with End_of_file -> ());
       Array.of_list (List.rev !beads))

let squared_distance x1 y1 x2 y2 =
  let dx = x1 -. x2 in
  let dy = y1 -. y2 in
  dx *. dx +. dy *. dy

let point_inside_bead ~margin x y (bead : bead) =
  squared_distance x y bead.bx bead.by
  < (bead.radius +. margin) ** 2.0

let bead_fits rows cols beads min_gap candidate =
  candidate.bx -. candidate.radius >= 0.0
  && candidate.by -. candidate.radius >= 0.0
  && candidate.bx +. candidate.radius <= float_of_int cols
  && candidate.by +. candidate.radius <= float_of_int rows
  && Array.for_all
       (fun (b : bead) ->
          let required =
            b.radius +. candidate.radius +. min_gap
          in
          squared_distance b.bx b.by candidate.bx candidate.by
          >= required *. required)
       beads

let generate_random_beads rng rows cols count radius min_gap =
  if radius <= 0.0 then
    invalid_arg "Zoospore HMM beads: BEAD_RADIUS must be positive";
  let placed : bead array ref = ref [||] in
  let attempts = ref 0 in
  let max_attempts = max 1000 (count * 10000) in
  while Array.length !placed < count && !attempts < max_attempts do
    incr attempts;
    let candidate = {
      bx = radius +. Rng.float rng (float_of_int cols -. 2.0 *. radius);
      by = radius +. Rng.float rng (float_of_int rows -. 2.0 *. radius);
      radius;
    } in
    if bead_fits rows cols !placed min_gap candidate then
      placed := Array.append !placed [|candidate|]
  done;
  if Array.length !placed <> count then
    failwith
      (Printf.sprintf
         "Zoospore HMM beads: could place only %d/%d random beads"
         (Array.length !placed) count);
  !placed

let beads_of_params rng params grid =
  match params.bead_source with
  | No_beads -> [||]
  | Beads_from_file filename ->
      let beads = load_beads filename params.bead_radius in
      Array.iter
        (fun (bead : bead) ->
           if bead.radius <= 0.0 then
             invalid_arg "Zoospore HMM beads: all bead radii must be positive")
        beads;
      beads
  | Random_beads count ->
      generate_random_beads
        rng (Grid.rows grid) (Grid.cols grid)
        count params.bead_radius params.bead_min_gap

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

let median_of_quantile_dist dist =
  let n = Array.length dist.probs in
  let rec find i =
    if i >= n - 1 || 0.5 <= dist.probs.(i + 1) then i
    else find (i + 1)
  in
  if 0.5 <= dist.probs.(0) then dist.values.(0)
  else if 0.5 >= dist.probs.(n - 1) then dist.values.(n - 1)
  else
    let i = find 0 in
    let p0 = dist.probs.(i) in
    let p1 = dist.probs.(i + 1) in
    let v0 = dist.values.(i) in
    let v1 = dist.values.(i + 1) in
    if p1 = p0 then v0
    else v0 +. (0.5 -. p0) *. (v1 -. v0) /. (p1 -. p0)

let load_hmm ~transition_file ~start_file ~quantile_file =
  let transition_matrix = read_transition_matrix transition_file in
  let n_states = Array.length transition_matrix in
  let start_probabilities =
    read_start_probabilities start_file n_states
  in
  let state_distributions =
    read_state_quantiles quantile_file n_states
  in
  let slow_state =
    let selected = ref 0 in
    let selected_median =
      ref (median_of_quantile_dist state_distributions.(0).speed)
    in
    for state = 1 to n_states - 1 do
      let median =
        median_of_quantile_dist state_distributions.(state).speed
      in
      if median < !selected_median then begin
        selected := state;
        selected_median := median
      end
    done;
    !selected
  in
  {
    n_states;
    start_probabilities;
    transition_matrix;
    state_distributions;
    slow_state;
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

let initial_agents rng params grid beads =
  let candidates =
    Initial_geometry.select grid (geometry_of_params params)
    |> Array.to_list
    |> List.filter (fun coord ->
           let x = float_of_int coord.Grid.col +. 0.5 in
           let y = float_of_int coord.Grid.row +. 0.5 in
           Array.for_all
             (fun bead ->
                not
                  (point_inside_bead
                     ~margin:params.zoospore_radius x y bead))
             beads)
    |> Array.of_list
  in
  if Array.length candidates < params.agents then
    failwith
      (Printf.sprintf
         "Zoospore HMM beads: only %d accessible cells for %d agents"
         (Array.length candidates) params.agents);
  let coords =
    Initial_geometry.random_subset rng ~n:params.agents candidates
  in
  Array.mapi
    (fun id coord ->
       (* Independent draw S0 ~ pi for every simulated agent. *)
       let hmm_state =
         sample_categorical rng params.hmm.start_probabilities
       in
       {
         id;
         x = float_of_int coord.Grid.col +. 0.5;
         y = float_of_int coord.Grid.row +. 0.5;
         age = 1;
         heading_deg = Rng.float rng 360.0;
         (* No observation has yet been emitted at frame 0. *)
         speed_um_s = 0.0;
         hmm_state;
         emitted_state = hmm_state;
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

let vector_norm x y = sqrt (x *. x +. y *. y)

let heading_of_vector dx dy fallback =
  if vector_norm dx dy <= 1e-15 then fallback
  else normalize_degrees (atan2 dy dx *. 180.0 /. Float.pi)

let first_segment_circle_hit x0 y0 dx dy bead inflated_radius =
  let fx = x0 -. bead.bx in
  let fy = y0 -. bead.by in
  let a = dx *. dx +. dy *. dy in
  if a <= 1e-18 then None
  else
    let b = 2.0 *. (fx *. dx +. fy *. dy) in
    let c =
      fx *. fx +. fy *. fy -. inflated_radius *. inflated_radius
    in
    let discriminant = b *. b -. 4.0 *. a *. c in
    if discriminant < 0.0 then None
    else
      let root = sqrt discriminant in
      let t1 = (-.b -. root) /. (2.0 *. a) in
      let t2 = (-.b +. root) /. (2.0 *. a) in
      let valid value = value > 1e-9 && value <= 1.0 in
      if valid t1 then Some t1
      else if valid t2 then Some t2
      else None

let earliest_bead_hit x y dx dy beads zoospore_radius =
  let best = ref None in
  Array.iter
    (fun bead ->
       match
         first_segment_circle_hit
           x y dx dy bead (bead.radius +. zoospore_radius)
       with
       | None -> ()
       | Some hit ->
           match !best with
           | None -> best := Some (hit, bead)
           | Some (best_hit, _) when hit < best_hit ->
               best := Some (hit, bead)
           | Some _ -> ())
    beads;
  !best

let move_with_bead_collisions params beads x0 y0 heading distance =
  let rec loop iteration x y dir_x dir_y remaining travelled =
    if iteration >= 4 || remaining <= 1e-12 then
      x, y, heading_of_vector dir_x dir_y heading,
      travelled, iteration > 0
    else
      let dx = remaining *. dir_x in
      let dy = remaining *. dir_y in
      match
        earliest_bead_hit
          x y dx dy beads params.zoospore_radius
      with
      | None ->
          x +. dx, y +. dy,
          heading_of_vector dir_x dir_y heading,
          travelled +. remaining,
          iteration > 0
      | Some (hit, bead) ->
          let pre_distance =
            max 0.0 (hit *. remaining -. 1e-9)
          in
          let contact_x = x +. pre_distance *. dir_x in
          let contact_y = y +. pre_distance *. dir_y in
          match params.collision_response with
          | Slowdown ->
              contact_x, contact_y,
              heading_of_vector dir_x dir_y heading,
              travelled +. pre_distance,
              true
          | Tangential | Both ->
              let nx0 = contact_x -. bead.bx in
              let ny0 = contact_y -. bead.by in
              let normal_norm =
                max 1e-15 (vector_norm nx0 ny0)
              in
              let nx = nx0 /. normal_norm in
              let ny = ny0 /. normal_norm in
              let normal_component =
                dir_x *. nx +. dir_y *. ny
              in
              let tx0 =
                dir_x -. normal_component *. nx
              in
              let ty0 =
                dir_y -. normal_component *. ny
              in
              let tangent_fraction = vector_norm tx0 ty0 in
              let remaining_after_contact =
                max 0.0 (remaining -. pre_distance)
              in
              if tangent_fraction <= 1e-12 then
                contact_x, contact_y, heading,
                travelled +. pre_distance, true
              else
                let tx = tx0 /. tangent_fraction in
                let ty = ty0 /. tangent_fraction in
                let factor =
                  match params.collision_response with
                  | Tangential -> 1.0
                  | Both -> params.collision_slowdown
                  | Slowdown -> assert false
                in
                let tangential_distance =
                  remaining_after_contact
                  *. tangent_fraction
                  *. factor
                in
                loop
                  (iteration + 1)
                  contact_x contact_y tx ty
                  tangential_distance
                  (travelled +. pre_distance)
  in
  let theta = heading *. Float.pi /. 180.0 in
  loop 0 x0 y0 (cos theta) (sin theta) distance 0.0

let move_agent params grid beads ag heading speed =
  let intended_distance =
    speed *. params.dt /. params.microns_per_cell
  in
  let x1, y1, collision_heading, travelled, collided =
    move_with_bead_collisions
      params beads ag.x ag.y heading intended_distance
  in
  let x2, y2, final_heading =
    match params.topology with
    | Grid.Toroidal ->
        wrap_coordinate (Grid.cols grid) x1,
        wrap_coordinate (Grid.rows grid) y1,
        collision_heading
    | Grid.Bounded ->
        if x1 >= 0.0
           && x1 < float_of_int (Grid.cols grid)
           && y1 >= 0.0
           && y1 < float_of_int (Grid.rows grid)
        then
          x1, y1, collision_heading
        else
          let reflected =
            reflected_heading
              (Grid.rows grid)
              (Grid.cols grid)
              x1 y1 collision_heading
          in
          let theta2 =
            reflected *. Float.pi /. 180.0
          in
          let remaining =
            max 0.0 (intended_distance -. travelled)
          in
          let rx = ag.x +. remaining *. cos theta2 in
          let ry = ag.y +. remaining *. sin theta2 in
          clamp 0.0
            (float_of_int (Grid.cols grid) -. 1e-9) rx,
          clamp 0.0
            (float_of_int (Grid.rows grid) -. 1e-9) ry,
          reflected
  in
  let realised_speed =
    travelled *. params.microns_per_cell /. params.dt
  in
  let actual_speed =
    if collided then
      realised_speed *. params.collision_speed_factor
    else
      realised_speed
  in
  x2, y2, final_heading, actual_speed, collided

let step_agent rng params grid beads ag =
  let emitted_state = ag.hmm_state in
  let distribution =
    params.hmm.state_distributions.(emitted_state)
  in
  let proposed_speed =
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
  let x, y, heading_deg, realised_speed, collided =
    move_agent
      params grid beads ag proposed_heading proposed_speed
  in
  let sampled_next_state =
    sample_categorical
      rng params.hmm.transition_matrix.(emitted_state)
  in
  let final_emitted_state =
    if collided then params.hmm.slow_state
    else emitted_state
  in
  let next_state =
    if collided then params.hmm.slow_state
    else sampled_next_state
  in
  {
    ag with
    x;
    y;
    age = min params.max_age (ag.age + 1);
    heading_deg;
    speed_um_s = realised_speed;
    hmm_state = next_state;
    emitted_state = final_emitted_state;
  }

let step_agents rng params grid beads agents =
  Array.map (step_agent rng params grid beads) agents

let empty_frame grid =
  Array.init
    (Grid.rows grid)
    (fun _ -> Array.make (Grid.cols grid) 0)

let frame_of_agents grid bead_display_state beads agents =
  let frame = empty_frame grid in
  Array.iter
    (fun bead ->
       let min_col =
         max 0
           (int_of_float
              (Float.floor (bead.bx -. bead.radius)))
       in
       let max_col =
         min (Grid.cols grid - 1)
           (int_of_float
              (Float.floor (bead.bx +. bead.radius)))
       in
       let min_row =
         max 0
           (int_of_float
              (Float.floor (bead.by -. bead.radius)))
       in
       let max_row =
         min (Grid.rows grid - 1)
           (int_of_float
              (Float.floor (bead.by +. bead.radius)))
       in
       for row = min_row to max_row do
         for col = min_col to max_col do
           let x = float_of_int col +. 0.5 in
           let y = float_of_int row +. 0.5 in
           if point_inside_bead ~margin:0.0 x y bead then
             frame.(row).(col) <- bead_display_state
         done
       done;
       let centre_col =
         int_of_float (Float.floor bead.bx)
       in
       let centre_row =
         int_of_float (Float.floor bead.by)
       in
       if centre_row >= 0
          && centre_row < Grid.rows grid
          && centre_col >= 0
          && centre_col < Grid.cols grid
       then
         frame.(centre_row).(centre_col) <-
           bead_display_state)
    beads;
  Array.iter
    (fun ag ->
       let coord = coord_of_agent ag in
       if Grid.valid grid coord then
         frame.(coord.Grid.row).(coord.col) <-
           state_of_agent ag)
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
  let bead_rng =
    Rng.create (params.seed lxor 0x5bd1e995)
  in
  let beads = beads_of_params bead_rng params grid in
  let bead_display_state = params.hmm.n_states + 1 in
  let agents = ref (initial_agents rng params grid beads) in
  let record generation =
    Array.iter
      (fun ag ->
         trace := trace_record generation ag :: !trace)
      !agents
  in
  frames.(0) <- frame_of_agents grid bead_display_state beads !agents;
  record 0;
  for generation = 1 to generations do
    agents := step_agents rng params grid beads !agents;
    frames.(generation) <-
      frame_of_agents grid bead_display_state beads !agents;
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
  | s -> Some (min (s - 1) 255)

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
    "beads", string_of_bead_source params.bead_source;
    "bead_radius", string_of_float params.bead_radius;
    "zoospore_radius", string_of_float params.zoospore_radius;
    "bead_min_gap", string_of_float params.bead_min_gap;
    "collision_response",
      string_of_collision_response params.collision_response;
    "collision_slowdown",
      string_of_float params.collision_slowdown;
    "collision_speed_factor",
      string_of_float params.collision_speed_factor;
    "collision_state", string_of_int params.hmm.slow_state;
    "collision_state_rule", "state with lowest median speed";
    "state_dynamics", "standard HMM: current-state emission then transition";
    "initial_state_usage", "first movement emitted from fitted start distribution";
    "speed_distribution", "state-conditional empirical inverse CDF";
    "turn_distribution", "state-conditional empirical inverse CDF";
    "emission_factorisation", "speed and turn sampled independently conditional on state";
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
  if hmm.n_states <> 2 then
    invalid_arg
      (Printf.sprintf
         "Zoospore HMM: this plugin expects exactly two hidden states, got %d"
         hmm.n_states);
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
    dt = arg_float "DT" 0.075 plugin_args;
    max_age = arg_int "MAX_AGE" 255 plugin_args;
    bead_source =
      parse_bead_source
        (arg_string "BEADS" "NONE" plugin_args)
        (arg_string "BEAD_MAP" "" plugin_args)
        (arg_int "BEAD_COUNT" 0 plugin_args);
    bead_radius =
      arg_float "BEAD_RADIUS" 0.5 plugin_args;
    zoospore_radius =
      arg_float "ZOOSPORE_RADIUS" 0.5 plugin_args;
    bead_min_gap =
      arg_float "BEAD_MIN_GAP" 0.0 plugin_args;
    collision_response =
      parse_collision_response
        (arg_string "COLLISION_RESPONSE" "TANGENT" plugin_args);
    collision_slowdown =
      arg_float "COLLISION_SLOWDOWN" 0.5 plugin_args;
    collision_speed_factor =
      arg_float "COLLISION_SPEED_FACTOR" 1.0 plugin_args;
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
  if params.bead_radius <= 0.0 then
    invalid_arg "Zoospore HMM beads: BEAD_RADIUS must be positive";
  if params.zoospore_radius < 0.0 then
    invalid_arg "Zoospore HMM beads: ZOOSPORE_RADIUS must be non-negative";
  if params.bead_min_gap < 0.0 then
    invalid_arg "Zoospore HMM beads: BEAD_MIN_GAP must be non-negative";
  if params.collision_slowdown < 0.0
     || params.collision_slowdown > 1.0
  then
    invalid_arg
      "Zoospore HMM beads: COLLISION_SLOWDOWN must lie in [0,1]";
  if params.collision_speed_factor < 0.0
     || params.collision_speed_factor > 1.0
  then
    invalid_arg
      "Zoospore HMM beads: COLLISION_SPEED_FACTOR must lie in [0,1]";

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
    "Two-state zoospore HMM with bead obstacles and collision-induced slowing";
  state_count = 3;
  to_color_index;
  run;
  export_xml;
}

let models = [ model ]
