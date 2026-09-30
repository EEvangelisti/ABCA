open Abca

module Binary_codec = struct
  type t = int

  let to_int32 = Int32.of_int
  let of_int32 = Int32.to_int
end

let pi = 4. *. atan 1.

let assoc key args =
  let key = String.uppercase_ascii key in
  List.find_map
    (fun (k, v) ->
      if String.uppercase_ascii k = key then
        Some v
      else
        None)
    args

let sf a k d =
  match assoc k a with
  | None -> d
  | Some x -> float_of_string x

let si a k d =
  match assoc k a with
  | None -> d
  | Some x -> int_of_string x

let ss a k d =
  match assoc k a with
  | None -> d
  | Some x -> x

let split c s =
  String.split_on_char c s
  |> List.map String.trim
  |> List.filter (( <> ) "")

let floats s =
  split ',' s |> List.map float_of_string |> Array.of_list

let sample rng a =
  if Array.length a = 0 then
    failwith "empty table"
  else
    a.(Rng.int rng (Array.length a))

let gauss rng =
  let u = max 1e-12 (Rng.float rng 1.) in
  sqrt (-2. *. log u) *. cos (2. *. pi *. Rng.float rng 1.)

let read_params filename =
  if filename = "" then
    []
  else
    let ic = open_in filename in
    Fun.protect
      ~finally:(fun () -> close_in_noerr ic)
      (fun () ->
        let rec loop acc =
          match input_line ic with
          | line ->
              let line = String.trim line in
              if line = "" || line.[0] = '#' then
                loop acc
              else
                (match String.split_on_char '=' line with
                | [ key; value ] ->
                    loop
                      ( ( String.uppercase_ascii (String.trim key),
                          String.trim value )
                      :: acc )
                | _ -> failwith ("bad parameter line: " ^ line))
          | exception End_of_file -> List.rev acc
        in
        loop [])

let params_filename plugin_args =
  match assoc "PARAMS" plugin_args with
  | Some filename -> filename
  | None ->
      match assoc "PARAM" plugin_args with
      | Some filename -> filename
      | None -> (
          match assoc "PARAM_FILE" plugin_args with
          | Some filename -> filename
          | None -> "")

let args plugin_args =
  let filename = params_filename plugin_args in
  let file_args = read_params filename in
  plugin_args @ file_args

let table a key smoke_defaults =
  match assoc key a with
  | Some x -> floats x
  | None ->
      if sf a "SMOKE_DEFAULTS" 0. = 1. then
        floats smoke_defaults
      else
        failwith
          (key ^ " required (or SMOKE_DEFAULTS=1 for non-fitted smoke test)")

let matrix a key n smoke_defaults =
  let x = table a key smoke_defaults in
  if Array.length x <> n * n then failwith (key ^ " wrong size");
  x

let choose rng probs =
  let u = Rng.float rng 1. in
  let rec loop i cumulative =
    if i = Array.length probs - 1 || u <= cumulative +. probs.(i) then
      i
    else
      loop (i + 1) (cumulative +. probs.(i))
  in
  loop 0 0.

let row m n i =
  Array.init n (fun j -> m.((i * n) + j))

let choose_matrix_row rng m n i =
  let u = Rng.float rng 1. in
  let base = i * n in
  let rec loop j cumulative =
    if j = n - 1 || u <= cumulative +. m.(base + j) then
      j
    else
      loop (j + 1) (cumulative +. m.(base + j))
  in
  loop 0 0.

let reflect limit x heading axis =
  let rec loop x heading =
    if x < 0. then
      loop (-.x) (if axis = 0 then pi -. heading else -.heading)
    else if x > limit then
      loop
        ((2. *. limit) -. x)
        (if axis = 0 then pi -. heading else -.heading)
    else
      (x, heading)
  in
  loop x heading

type agent = {
  id : int;
  mutable x : float;
  mutable y : float;
  mutable h : float;
  mutable speed : float;
  mutable turn : float;
  mutable vx : float;
  mutable vy : float;
  mutable state : int;
  mutable dwell : int;
  mutable age : int;
  length : int;
}

type spec = {
  id : string;
  rule : string;
}

type vector_transition = {
  previous_speed : float;
  next_speed : float;
  next_turn : float;
}

type prepared = {
  dt : float;
  microns_per_cell : float;
  speed_table : float array;
  turn_table : float array;
  turn_innov_table : float array;
  pair_table : float array;
  vector_table : vector_transition array;
  match_tol : float;
  turn_phi : float;
  speed_mean : float;
  speed_sd : float;
  turn_sd_rad : float;
  ou_theta : float;
  ou_speed_mean : float;
  ou_sigma : float;
  ou_turn_sd_rad : float;
  transition : float array;
  speed0 : float array;
  speed1 : float array;
  turn0 : float array;
  turn1 : float array;
  duration0 : float array;
  duration1 : float array;
  a_matrix : float array;
  q_matrix : float array;
  speed_offset : float;
  speed_scale : float;
  turn_offset : float;
  turn_scale : float;
  hmm_k : int;
  hmm_means : float array;
  hmm_sds : float array;
}

let empty = [||]

let prepare spec a =
  let dt = sf a "DT" 0.0700506 in
  if dt <= 0. then invalid_arg "DT must be > 0";
  let microns_per_cell = sf a "MICRONS_PER_CELL" 1. in
  if microns_per_cell <= 0. then invalid_arg "MICRONS_PER_CELL must be > 0";

  (* Only the tables required by the selected model are parsed.  All parsing
     happens once here, before the simulation loop. *)
  let speed_table =
    match spec.rule with
    | "iid" | "crw" -> table a "SPEED_TABLE" "30,50,70"
    | _ -> empty
  in
  let turn_table =
    if spec.rule = "iid" then table a "TURN_TABLE" "-20,0,20" else empty
  in
  let turn_innov_table =
    if spec.rule = "crw" then table a "TURN_INNOV_TABLE" "-10,0,10" else empty
  in
  let pair_table =
    if spec.rule = "pair" then begin
      let x = table a "PAIR_TABLE" "30,-20,50,0,70,20" in
      if Array.length x mod 2 <> 0 then failwith "PAIR_TABLE";
      x
    end else empty
  in
  let vector_table =
    if spec.rule = "vector1" then begin
      let x = table a "VECTOR_PAIR_TABLE" "30,-20,50,0,50,0,70,20" in
      if Array.length x mod 4 <> 0 then failwith "VECTOR_PAIR_TABLE";
      let n = Array.length x / 4 in
      let v = Array.init n (fun i ->
        {
          previous_speed = x.(4 * i);
          next_speed = x.((4 * i) + 2);
          next_turn = x.((4 * i) + 3) *. pi /. 180.;
        })
      in
      Array.sort
        (fun u v -> Float.compare u.previous_speed v.previous_speed)
        v;
      v
    end else [||]
  in
  let transition =
    match spec.rule with
    | "markov" -> matrix a "TRANSITION" 2 ".97,.03,.05,.95"
    | "hmm" ->
        let k = si a "K" 2 in
        if k < 2 || k > 4 then failwith "K must be 2..4";
        matrix a "TRANSITION" k ".97,.03,.05,.95"
    | _ -> empty
  in
  let speed0, speed1, turn0, turn1 =
    match spec.rule with
    | "markov" | "semimarkov" ->
        ( table a "SPEED0" "25,35",
          table a "SPEED1" "55,70",
          table a "TURN0" "-25,0,25",
          table a "TURN1" "-8,0,8" )
    | _ -> (empty, empty, empty, empty)
  in
  let duration0, duration1 =
    if spec.rule = "semimarkov" then
      (table a "DURATION0" "10,20,30", table a "DURATION1" "10,20,30")
    else (empty, empty)
  in
  let a_matrix, q_matrix =
    if spec.rule = "var1" then
      (matrix a "A" 2 ".7,0,0,.6", matrix a "Q" 2 "1,0,0,1")
    else (empty, empty)
  in
  let hmm_k, hmm_means, hmm_sds =
    if spec.rule = "hmm" then begin
      let k = si a "K" 2 in
      let means = table a "MEANS" "30,0,65,0" in
      let sds = table a "SDS" "5,20,8,8" in
      if Array.length means <> 2 * k || Array.length sds <> 2 * k then
        failwith "MEANS/SDS size";
      (k, means, sds)
    end else (0, empty, empty)
  in
  {
    dt;
    microns_per_cell;
    speed_table;
    turn_table;
    turn_innov_table;
    pair_table;
    vector_table;
    match_tol = sf a "MATCH_TOL" 10.;
    turn_phi = sf a "TURN_PHI" 0.7;
    speed_mean = sf a "SPEED_MEAN" 50.;
    speed_sd = sf a "SPEED_SD" 5.;
    turn_sd_rad = sf a "TURN_SD_DEG" 12. *. pi /. 180.;
    ou_theta = sf a "OU_THETA" 2.;
    ou_speed_mean = sf a "OU_SPEED_MEAN" 50.;
    ou_sigma = sf a "OU_SIGMA" 10.;
    ou_turn_sd_rad = sf a "TURN_SD_DEG" 10. *. pi /. 180.;
    transition;
    speed0;
    speed1;
    turn0;
    turn1;
    duration0;
    duration1;
    a_matrix;
    q_matrix;
    speed_offset = sf a "SPEED_OFFSET" 50.;
    speed_scale = sf a "SPEED_SCALE" 10.;
    turn_offset = sf a "TURN_OFFSET" 0.;
    turn_scale = sf a "TURN_SCALE" 10.;
    hmm_k;
    hmm_means;
    hmm_sds;
  }

let emit_state p rng state =
  let speeds, turns =
    if state = 0 then (p.speed0, p.turn0) else (p.speed1, p.turn1)
  in
  (sample rng speeds, sample rng turns *. pi /. 180.)

let lower_bound_vector a x =
  let lo = ref 0 in
  let hi = ref (Array.length a) in
  while !lo < !hi do
    let mid = (!lo + !hi) / 2 in
    if a.(mid).previous_speed < x then lo := mid + 1 else hi := mid
  done;
  !lo

let upper_bound_vector a x =
  let lo = ref 0 in
  let hi = ref (Array.length a) in
  while !lo < !hi do
    let mid = (!lo + !hi) / 2 in
    if a.(mid).previous_speed <= x then lo := mid + 1 else hi := mid
  done;
  !lo

let update spec p rng q =
  (match spec.rule with
  | "iid" ->
      q.speed <- sample rng p.speed_table;
      q.turn <- sample rng p.turn_table *. pi /. 180.

  | "crw" ->
      q.speed <- sample rng p.speed_table;
      q.turn <-
        (p.turn_phi *. q.turn)
        +. (sample rng p.turn_innov_table *. pi /. 180.)

  | "pair" ->
      let i = 2 * Rng.int rng (Array.length p.pair_table / 2) in
      q.speed <- p.pair_table.(i);
      q.turn <- p.pair_table.(i + 1) *. pi /. 180.

  | "vector1" ->
      let n = Array.length p.vector_table in
      if n = 0 then failwith "empty VECTOR_PAIR_TABLE";
      let lo = lower_bound_vector p.vector_table (q.speed -. p.match_tol) in
      let hi = upper_bound_vector p.vector_table (q.speed +. p.match_tol) in
      let i = if lo < hi then lo + Rng.int rng (hi - lo) else Rng.int rng n in
      let v = p.vector_table.(i) in
      q.speed <- v.next_speed;
      q.turn <- v.next_turn

  | "prw" ->
      q.speed <- max 0. (p.speed_mean +. (p.speed_sd *. gauss rng));
      q.turn <- p.turn_sd_rad *. gauss rng

  | "ou" ->
      q.speed <-
        max 0.
          (q.speed
          +. (p.ou_theta *. (p.ou_speed_mean -. q.speed) *. p.dt)
          +. (p.ou_sigma *. sqrt p.dt *. gauss rng));
      q.turn <- p.ou_turn_sd_rad *. gauss rng

  | "markov" ->
      q.state <- choose_matrix_row rng p.transition 2 q.state;
      let speed, turn = emit_state p rng q.state in
      q.speed <- speed;
      q.turn <- turn

  | "semimarkov" ->
      if q.dwell <= 0 then begin
        q.state <- 1 - q.state;
        let durations = if q.state = 0 then p.duration0 else p.duration1 in
        q.dwell <- max 1 (int_of_float (sample rng durations))
      end;
      q.dwell <- q.dwell - 1;
      let speed, turn = emit_state p rng q.state in
      q.speed <- speed;
      q.turn <- turn

  | "var1" ->
      let z1 = gauss rng in
      let z2 = gauss rng in
      let e1 = sqrt (max 0. p.q_matrix.(0)) *. z1 in
      let e2 =
        (p.q_matrix.(2) /. sqrt (max 1e-12 p.q_matrix.(0)) *. z1)
        +. (sqrt
              (max 0.
                 (p.q_matrix.(3)
                 -. (p.q_matrix.(2) *. p.q_matrix.(2)
                    /. max 1e-12 p.q_matrix.(0))))
           *. z2)
      in
      let next_speed =
        (p.a_matrix.(0) *. q.speed) +. (p.a_matrix.(1) *. q.turn) +. e1
      in
      let next_turn =
        (p.a_matrix.(2) *. q.speed) +. (p.a_matrix.(3) *. q.turn) +. e2
      in
      q.speed <- max 0. (p.speed_offset +. (p.speed_scale *. next_speed));
      q.turn <- (p.turn_offset +. (p.turn_scale *. next_turn)) *. pi /. 180.

  | "hmm" ->
      let k = p.hmm_k in
      q.state <- choose_matrix_row rng p.transition k q.state;
      q.speed <-
        max 0.
          (p.hmm_means.(2 * q.state)
          +. (p.hmm_sds.(2 * q.state) *. gauss rng));
      q.turn <-
        (p.hmm_means.((2 * q.state) + 1)
        +. (p.hmm_sds.((2 * q.state) + 1) *. gauss rng))
        *. pi /. 180.

  | _ -> assert false);

  q.h <- q.h +. q.turn;
  let distance_cells = q.speed *. p.dt /. p.microns_per_cell in
  q.vx <- distance_cells *. cos q.h;
  q.vy <- distance_cells *. sin q.h;
  q.x <- q.x +. q.vx;
  q.y <- q.y +. q.vy;
  q.age <- q.age + 1

let lengths filename n default_length =
  if filename = "" then
    Array.make n default_length
  else
    let ic = open_in filename in
    let values = ref [] in
    (try
       while true do
         let line = String.trim (input_line ic) in
         try
           let value =
             int_of_string (List.hd (List.rev (split ',' line)))
           in
           values := value :: !values
         with _ -> ()
       done
     with End_of_file -> close_in ic);
    let values = Array.of_list (List.rev !values) in
    if Array.length values = 0 then
      Array.make n default_length
    else
      Array.init n (fun i -> values.(i mod Array.length values))


let specs =
  [
    ("c0_iid", "iid");
    ("c1_crw", "crw");
    ("c2_pair_bootstrap", "pair");
    ("c3_vector_bootstrap1", "vector1");
    ("c4_prw", "prw");
    ("c5_ou_velocity", "ou");
    ("c6_markov2", "markov");
    ("c7_semimarkov2", "semimarkov");
    ("c8_copula_var1", "var1");
    ("c9_gaussian_hmm", "hmm");
  ]

let normalize_model_name s =
  match String.lowercase_ascii (String.trim s) with
  | "c0" | "iid" | "c0_iid" -> "c0_iid"
  | "c1" | "crw" | "c1_crw" -> "c1_crw"
  | "c2" | "pair" | "c2_pair_bootstrap" -> "c2_pair_bootstrap"
  | "c3" | "vector1" | "vector" | "c3_vector_bootstrap1" ->
      "c3_vector_bootstrap1"
  | "c4" | "prw" | "c4_prw" -> "c4_prw"
  | "c5" | "ou" | "c5_ou_velocity" -> "c5_ou_velocity"
  | "c6" | "markov" | "c6_markov2" -> "c6_markov2"
  | "c7" | "semimarkov" | "semi-markov" | "c7_semimarkov2" ->
      "c7_semimarkov2"
  | "c8" | "var1" | "copula_var1" | "c8_copula_var1" ->
      "c8_copula_var1"
  | "c9" | "hmm" | "gaussian_hmm" | "c9_gaussian_hmm" ->
      "c9_gaussian_hmm"
  | x ->
      invalid_arg
        ("Unknown MODEL='" ^ x
       ^ "'. Expected c0..c9, a rule alias, or a full candidate name.")


let spec_of_model_name name =
  let id = normalize_model_name name in
  match List.assoc_opt id specs with
  | Some rule -> { id; rule }
  | None -> assert false

let run ~rows ~cols ~generations ~seed ~density:_ ~agents ~topology
    ~plugin_args ~output =
  let a = args plugin_args in
  let spec = spec_of_model_name (ss a "MODEL" "c0_iid") in
  let prepared = prepare spec a in
  let dt = prepared.dt in

  let n =
    match agents with
    | Some n -> n
    | None -> si a "AGENTS" 1
  in

  let rng = Rng.create seed in
  let track_lengths =
    lengths (ss a "TRACK_MANIFEST" "") n (generations + 1)
  in

  let init_mode = String.uppercase_ascii (ss a "INIT" "RANDOM") in
  let radius = sf a "RADIUS" 50. in
  let cx = sf a "CENTER_X" (float cols /. 2.) in
  let cy = sf a "CENTER_Y" (float rows /. 2.) in

  let initial_position () =
    match init_mode with
    | "RANDOM" | "UNIFORM" ->
        (Rng.float rng (float cols), Rng.float rng (float rows))
    | "DISK" ->
        let r = radius *. sqrt (Rng.float rng 1.) in
        let theta = Rng.float rng (2. *. pi) in
        (cx +. (r *. cos theta), cy +. (r *. sin theta))
    | "CIRCLE" ->
        let theta = Rng.float rng (2. *. pi) in
        (cx +. (radius *. cos theta), cy +. (radius *. sin theta))
    | x ->
        invalid_arg
          ("Unknown INIT='" ^ x ^ "'. Expected RANDOM, DISK, or CIRCLE.")
  in

  let population =
    Array.init n (fun id ->
        let x, y = initial_position () in
        {
          id;
          x = min (float cols -. 1e-9) (max 0. x);
          y = min (float rows -. 1e-9) (max 0. y);
          h = Rng.float rng (2. *. pi);
          speed = 0.;
          turn = 0.;
          vx = 0.;
          vy = 0.;
          state = 0;
          dwell = 0;
          age = 0;
          length = track_lengths.(id);
        })
  in

  let records = ref [] in

  let push frame q =
    if frame < q.length then
      records :=
        {
          Abca_io.Agent_trace.frame;
          id = q.id;
          x = q.x;
          y = q.y;
          row = min (rows - 1) (max 0 (int_of_float q.y));
          col = min (cols - 1) (max 0 (int_of_float q.x));
          angle = int_of_float (q.h *. 180. /. pi);
          age = q.age;
          state = q.state;
        }
        :: !records
  in

  let frames =
    Array.init (generations + 1) (fun frame_index ->
        let frame = Array.make_matrix rows cols 0 in

        Array.iter
          (fun q ->
            if frame_index > 0 && frame_index < q.length then begin
              update spec prepared rng q;

              match topology with
              | Grid.Toroidal ->
                  q.x <- mod_float (q.x +. float cols) (float cols);
                  q.y <- mod_float (q.y +. float rows) (float rows)

              | Grid.Bounded ->
                  let x, heading =
                    reflect (float cols -. 1e-9) q.x q.h 0
                  in
                  q.x <- x;
                  q.h <- heading;

                  let y, heading =
                    reflect (float rows -. 1e-9) q.y q.h 1
                  in
                  q.y <- y;
                  q.h <- heading
            end;

            if frame_index < q.length then begin
              push frame_index q;

              let row =
                min (rows - 1) (max 0 (int_of_float q.y))
              in
              let col =
                min (cols - 1) (max 0 (int_of_float q.x))
              in

              (* 0 is background; 1..4 encode the agent latent state. *)
              frame.(row).(col) <- 1 + min 3 (max 0 q.state)
            end)
          population;

        frame)
  in

  let smoke =
    if sf a "SMOKE_DEFAULTS" 0. = 1. then "true" else "false"
  in

  let params_file = params_filename plugin_args in

  let fitted =
    if smoke = "true" then
      "false"
    else if params_file <> "" then
      "true"
    else
      "unspecified"
  in

  let metadata =
    Abca_io.Metadata.of_list
      [
        ("model", spec.id);
        ("rule", spec.rule);
        ("version", "zoospores-multimodel/0.3.0-optimized");
        ("dt", string_of_float dt);
        ("seed", string_of_int seed);
        ("smoke_defaults", smoke);
        ("fitted", fitted);
        ("params_file", params_file);
        ("init", init_mode);
        ("radius", string_of_float radius);
        ("microns_per_cell", string_of_float prepared.microns_per_cell);
      ]
  in

  let archive =
    Abca_io.Binary.make_archive
      ~rows
      ~cols
      ~generation:generations
      ~metadata
      ~frames
      ~agents:(Array.of_list (List.rev !records))
      ()
  in

  Abca_io.Binary.save
    ~filename:output
    ~archive
    ~codec:(module Binary_codec)

let export ~input ~output =
  let archive =
    Abca_io.Binary.load
      ~filename:input
      ~codec:(module Binary_codec)
  in
  Abca_io.Xml.save_agent_trace_trackmate ~filename:output archive.agents

let models =
  [
    {
      Abca_models.Model.name = "zoospores-multimodel";
      family = Abca_models.Model.Biological;
      kind = Abca_models.Model.Agent_based_model;
      description =
        "Zoospore multimodel plugin; select C0-C9 with \
         --plugin-arg MODEL=... and parameters with \
         --plugin-arg PARAMS=path/to/file.params";
      state_count = 5;
      to_color_index = (function
        | 0 -> None
        | x -> Some x);
      run;
      export_xml = (fun ~input ~output -> export ~input ~output);
    };
  ]
