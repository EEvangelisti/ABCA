open Abca

(*
   Reconciled canonical portfolio, frozen specification 1.0.

   This plugin implements the 13 canonical zoospore-movement model classes
   obtained after cross-campaign reconciliation. The implementation itself
   contains no fitted numerical values: every fit-relevant parameter is loaded
   from a single external TOML parameter file.

   Design principles
   -----------------
   - One executable ABCA plugin exposes all reconciled model classes.
   - Model identity is explicit and provenance is retained per canonical mode.
   - Numerical parameters are externalised and validated before simulation.
   - All models share the same simulation/export infrastructure whenever their
     mathematical definitions permit it.
   - Empirical models additionally verify the SHA-256 checksum of their fitted
     transition tables or trajectory libraries before use.
*)


(* -------------------------------------------------------------------------- *)
(* Canonical model catalogue                                                  *)
(* -------------------------------------------------------------------------- *)

type kind =
  | Iid
  | Ballistic
  | Pcrw
  | Turn_ar1
  | Velocity_ou
  | Speed_turn
  | Switch_pause
  | Switch_turn
  | Switch_speed
  | Het_speed
  | Reversal
  | Emp_local
  | Emp_whole

type def = {
  name : string;
  label : string;
  provenance : string;
  kind : kind;
}

(*
   Each canonical definition carries:
   - a stable machine-readable identifier;
   - a human-readable description;
   - the discovery-campaign candidates from which it was reconciled;
   - the internal constructor used by the executable plugin.

   The provenance strings are descriptive metadata only: they do not alter
   simulation behaviour.
*)
let defs =
  [
    {
      name = "CAN-IID";
      label = "isotropic independent-direction null";
      provenance = "RUN2:isotropic-iid; RUN3:zoospore-iid";
      kind = Iid;
    };
    {
      name = "CAN-BALLISTIC";
      label = "constant-heading null";
      provenance = "RUN3:zoospore-ballistic; zero-turn limits";
      kind = Ballistic;
    };
    {
      name = "CAN-PCRW";
      label = "one-regime heading-persistent walk";
      provenance =
        "RUN1:persistent-crw,empirical-first-order-walk; \
         RUN2:straight-noisy; RUN3:zoospore-persistent";
      kind = Pcrw;
    };
    {
      name = "CAN-TURN-AR1";
      label = "stationary turn-memory walk";
      provenance = "RUN2:correlated-heading; RUN3:zoospore-memory";
      kind = Turn_ar1;
    };
    {
      name = "CAN-VELOCITY-OU";
      label = "Cartesian velocity persistence";
      provenance = "RUN2:velocity-ou";
      kind = Velocity_ou;
    };
    {
      name = "CAN-SPEED-TURN";
      label = "instantaneous speed-dependent turning";
      provenance = "RUN2:speed-turn-coupled; RUN3:zoospore-coupled";
      kind = Speed_turn;
    };
    {
      name = "CAN-SWITCH-PAUSE";
      label = "Markov move/pause persistent walk";
      provenance =
        "RUN1:two-state-persistent-walk; RUN1:pcrw-pauses variant lineage";
      kind = Switch_pause;
    };
    {
      name = "CAN-SWITCH-TURN";
      label = "Markov run/reorientation walk";
      provenance = "RUN2:run-reorientation; RUN2:CR-002; RUN1:C02 lineage";
      kind = Switch_turn;
    };
    {
      name = "CAN-SWITCH-SPEED";
      label = "Markov fast/slow persistent walk";
      provenance = "RUN3:zoospore-two-state";
      kind = Switch_speed;
    };
    {
      name = "CAN-HET-SPEED";
      label = "trajectory-level speed random effect";
      provenance = "RUN2:heterogeneous-agent; RUN3:zoospore-heterogeneous";
      kind = Het_speed;
    };
    {
      name = "CAN-REVERSAL";
      label = "persistent walk with explicit pi events";
      provenance = "RUN3:zoospore-reversal";
      kind = Reversal;
    };
    {
      name = "CAN-EMP-LOCAL";
      label = "empirical local transition generator";
      provenance =
        "RUN1:empirical-first-order-walk,persistent-crw; RUN1:C03";
      kind = Emp_local;
    };
    {
      name = "CAN-EMP-WHOLE";
      label = "whole-trajectory bootstrap benchmark";
      provenance = "RUN1:bootstrap-whole-trajectories";
      kind = Emp_whole;
    };
  ]


(* -------------------------------------------------------------------------- *)
(* ABCA serialisation codecs                                                  *)
(* -------------------------------------------------------------------------- *)

module Codec = struct
  type t = int

  let to_int32 = Int32.of_int
  let of_int32 = Int32.to_int
end

module Xml_codec = struct
  type t = int

  let to_string = string_of_int
end


(* -------------------------------------------------------------------------- *)
(* Small utility functions                                                    *)
(* -------------------------------------------------------------------------- *)

let pi = 4.0 *. atan 1.0

let finite x =
  match classify_float x with
  | FP_normal | FP_subnormal | FP_zero -> true
  | _ -> false

let trim = String.trim
let lowercase = String.lowercase_ascii

let starts_with s p =
  String.length s >= String.length p
  && String.sub s 0 (String.length p) = p

(* Remove TOML comments while preserving '#' characters inside quoted strings. *)
let strip_comment line =
  let rec loop i quoted =
    if i = String.length line then
      line
    else
      match line.[i] with
      | '"' -> loop (i + 1) (not quoted)
      | '#' when not quoted -> String.sub line 0 i
      | _ -> loop (i + 1) quoted
  in
  loop 0 false

let split_once c s =
  match String.index_opt s c with
  | None ->
      failwith
        ("parameter file: expected '" ^ String.make 1 c ^ "' in: " ^ s)
  | Some i ->
      ( trim (String.sub s 0 i),
        trim (String.sub s (i + 1) (String.length s - i - 1)) )

let unquote s =
  let n = String.length s in
  if n >= 2 && s.[0] = '"' && s.[n - 1] = '"' then
    String.sub s 1 (n - 2)
  else
    s


(* -------------------------------------------------------------------------- *)
(* Minimal TOML reader                                                        *)
(* -------------------------------------------------------------------------- *)

(*
   The plugin intentionally uses a small, strict TOML subset:
   [section] headers followed by scalar key = value entries.

   Full semantic validation is delegated to Schema_validation below. This keeps
   the runtime parser small while allowing the schema to reject missing,
   duplicate, unknown, malformed or out-of-domain parameters.
*)
type table = (string * (string * string) list) list

let load_toml filename : table =
  let ic =
    try open_in filename
    with Sys_error e -> failwith ("cannot open PARAMETER_FILE: " ^ e)
  in
  Fun.protect
    ~finally:(fun () -> close_in_noerr ic)
    (fun () ->
      let section = ref "" in
      let acc = ref [] in

      let add key value =
        let prior =
          match List.assoc_opt !section !acc with
          | Some x -> x
          | None -> []
        in
        if List.mem_assoc key prior then
          failwith
            ("parameter file: duplicate key " ^ !section ^ "." ^ key);
        acc :=
          (!section, (key, value) :: prior)
          :: List.remove_assoc !section !acc
      in

      (try
         while true do
           let line = trim (strip_comment (input_line ic)) in
           if line <> "" then
             if line.[0] = '[' then begin
               let n = String.length line in
               if n < 3 || line.[n - 1] <> ']' then
                 failwith ("parameter file: malformed section: " ^ line);
               let name = trim (String.sub line 1 (n - 2)) in
               if List.mem_assoc name !acc then
                 failwith
                   ("parameter file: duplicate section [" ^ name ^ "]");
               section := name;
               acc := (name, []) :: !acc
             end
             else begin
               if !section = "" then
                 failwith "parameter file: key outside section";
               let k, v = split_once '=' line in
               if k = "" then failwith "parameter file: empty key";
               add k (unquote v)
             end
         done
       with End_of_file -> ());

      List.rev_map
        (fun (name, entries) -> (name, List.rev entries))
        !acc)

include Schema_validation


(* -------------------------------------------------------------------------- *)
(* Parameter access and domain checking                                       *)
(* -------------------------------------------------------------------------- *)

let section tbl name =
  match List.assoc_opt name tbl with
  | Some x -> x
  | None -> failwith ("missing required parameter section [" ^ name ^ "]")

let value sec key =
  match List.assoc_opt key sec with
  | Some x -> x
  | None -> failwith ("missing required parameter '" ^ key ^ "'")

let as_float sec key =
  let s = value sec key in
  let x =
    try float_of_string s
    with _ -> failwith (key ^ " must be a float")
  in
  if not (finite x) then failwith (key ^ " must be finite");
  x

let as_int sec key =
  try int_of_string (value sec key)
  with _ -> failwith (key ^ " must be an integer")

let as_bool sec key =
  match lowercase (value sec key) with
  | "true" -> true
  | "false" -> false
  | _ -> failwith (key ^ " must be boolean")

let as_enum sec key allowed =
  let x = value sec key in
  if not (List.mem x allowed) then
    failwith
      (key ^ " must be one of: " ^ String.concat ", " allowed);
  x

let require_range key lo hi x =
  if x < lo || x > hi then
    failwith
      (Printf.sprintf "%s must be in [%g,%g]" key lo hi)

let require_nonneg key x =
  if x < 0. then failwith (key ^ " must be >= 0")

let require_pos key x =
  if x <= 0. then failwith (key ^ " must be > 0")

let require_open key lo hi x =
  if x <= lo || x >= hi then
    failwith
      (Printf.sprintf "%s must be in (%g,%g)" key lo hi)


(* -------------------------------------------------------------------------- *)
(* Plugin argument handling                                                   *)
(* -------------------------------------------------------------------------- *)

let find_arg key args =
  let key = String.uppercase_ascii key in
  List.find_map
    (fun (k, v) ->
      if String.uppercase_ascii k = key then Some v else None)
    args

let parameter_file args =
  match find_arg "PARAMETER_FILE" args with
  | Some x when trim x <> "" -> x
  | _ ->
      failwith
        "required --plugin-arg PARAMETER_FILE=<path> is missing"

type init_mode =
  | Init_center
  | Init_circle of float

let initialisation args =
  let mode =
    match find_arg "INIT" args with
    | None -> "CENTER"
    | Some x -> String.uppercase_ascii (trim x)
  in
  match mode with
  | "CENTER" ->
      (match find_arg "RADIUS" args with
      | None -> Init_center
      | Some _ ->
          failwith
            "RADIUS is only valid with --plugin-arg INIT=CIRCLE")
  | "DISK" | "CIRCLE" ->
      let radius =
        match find_arg "RADIUS" args with
        | None ->
            failwith
              "INIT=DISK/CIRCLE requires --plugin-arg RADIUS=<positive radius>"
        | Some x ->
            (try float_of_string (trim x)
             with Failure _ ->
               failwith "RADIUS must be a floating-point value")
      in
      if not (finite radius) || radius <= 0. then
        failwith "RADIUS must be finite and > 0";
      Init_circle radius
  | x ->
      failwith
        ("unsupported INIT=" ^ x ^ "; expected CENTER, DISK or CIRCLE")

let reject_unknown_args args =
  let allowed = [ "PARAMETER_FILE"; "INIT"; "RADIUS" ] in
  List.iter
    (fun (k, _) ->
      let ku = String.uppercase_ascii k in
      if not (List.mem ku allowed) then
        failwith
          ("unknown plugin argument "
          ^ k
          ^ "; accepted arguments are PARAMETER_FILE, INIT and RADIUS"))
    args


(* -------------------------------------------------------------------------- *)
(* Random variates and geometry                                               *)
(* -------------------------------------------------------------------------- *)

(* Standard normal using Box-Muller, consistent with the frozen specification. *)
let normal rng =
  let u1 = max 1e-300 (Rng.float rng 1.0) in
  let u2 = Rng.float rng 1.0 in
  sqrt (-2.0 *. log u1) *. cos (2.0 *. pi *. u2)

let wrap_angle x =
  let y = mod_float (x +. pi) (2.0 *. pi) in
  (if y < 0. then y +. (2.0 *. pi) else y) -. pi

let clamp lo hi x =
  max lo (min hi x)

(*
   Recursive specular reflection.

   Coordinates are simulated continuously. When an update crosses a boundary,
   the corresponding coordinate and velocity component are reflected until the
   position lies inside the bounded domain. The heading is updated consistently.
   The returned hit count is recorded as run metadata.
*)
let apply_boundary rows cols x y heading vx vy =
  let xmax = float_of_int cols in
  let ymax = float_of_int rows in

  let rec rx x h vx hits =
    if x < 0. then
      rx (-.x) (pi -. h) (-.vx) (hits + 1)
    else if x >= xmax then
      rx (2.0 *. xmax -. x) (pi -. h) (-.vx) (hits + 1)
    else
      (x, h, vx, hits)
  in

  let rec ry y h vy hits =
    if y < 0. then
      ry (-.y) (-.h) (-.vy) (hits + 1)
    else if y >= ymax then
      ry (2.0 *. ymax -. y) (-.h) (-.vy) (hits + 1)
    else
      (y, h, vy, hits)
  in

  let x, h, vx, hx = rx x heading vx 0 in
  let y, h, vy, hy = ry y h vy 0 in
  (x, y, wrap_angle h, vx, vy, hx + hy)


(* -------------------------------------------------------------------------- *)
(* Integrity checks for empirical fitting artefacts                           *)
(* -------------------------------------------------------------------------- *)

let sha256_file filename =
  let q = Filename.quote filename in
  let ic = Unix.open_process_in ("sha256sum " ^ q) in
  Fun.protect
    ~finally:(fun () -> ignore (Unix.close_process_in ic))
    (fun () ->
      let line = input_line ic in
      match String.split_on_char ' ' line with
      | h :: _ -> h
      | _ -> failwith "sha256sum output malformed")

let check_sha filename expected =
  if String.length expected <> 64 then
    failwith "SHA-256 must have 64 hexadecimal characters";
  if lowercase (sha256_file filename) <> lowercase expected then
    failwith ("SHA-256 mismatch for " ^ filename)


(* -------------------------------------------------------------------------- *)
(* Empirical transition/library readers                                       *)
(* -------------------------------------------------------------------------- *)

let read_data_lines filename =
  let ic =
    try open_in filename
    with Sys_error e ->
      failwith ("cannot open empirical data file: " ^ e)
  in
  Fun.protect
    ~finally:(fun () -> close_in_noerr ic)
    (fun () ->
      let rec loop acc =
        match input_line ic with
        | line ->
            let line = trim (strip_comment line) in
            loop (if line = "" then acc else line :: acc)
        | exception End_of_file -> List.rev acc
      in
      loop [])

(* CAN-EMP-LOCAL expects one "step_um,turn_rad" transition per line. *)
let parse_pair line =
  match List.map trim (String.split_on_char ',' line) with
  | [ a; b ] ->
      let x = float_of_string a in
      let y = float_of_string b in
      if not (finite x && finite y) then
        failwith "non-finite empirical transition";
      (x, y)
  | _ ->
      failwith
        ("transition table line must be step_um,turn_rad: " ^ line)

let load_transitions path sha =
  check_sha path sha;
  let a =
    Array.of_list
      (List.map parse_pair (read_data_lines path))
  in
  if Array.length a = 0 then
    failwith "empty transition table";
  a

let split_ws s =
  List.filter
    ((<>) "")
    (String.split_on_char ' '
       (String.map (fun c -> if c = '\t' then ' ' else c) s))

(* CAN-EMP-WHOLE expects whitespace-separated "dx,dy" tokens per trajectory. *)
let parse_displacement token =
  match List.map trim (String.split_on_char ',' token) with
  | [ a; b ] ->
      let x = float_of_string a in
      let y = float_of_string b in
      if not (finite x && finite y) then
        failwith "non-finite displacement";
      (x, y)
  | _ ->
      failwith ("displacement must be dx,dy: " ^ token)

let load_library path sha =
  check_sha path sha;
  let a =
    Array.of_list
      (List.map
         (fun line ->
           Array.of_list
             (List.map parse_displacement (split_ws line)))
         (read_data_lines path))
  in
  if
    Array.length a = 0
    || Array.exists (fun x -> Array.length x = 0) a
  then
    failwith "empty trajectory library/trajectory";
  a


(* -------------------------------------------------------------------------- *)
(* Shared simulation protocol                                                 *)
(* -------------------------------------------------------------------------- *)

type common = {
  dt : float;
  agents : int;
  initial_position : string;
  initial_heading : string;
  boundary : string;
  record_initial : bool;
}

let load_common tbl =
  let s = section tbl "common" in
  let c =
    {
      dt = as_float s "dt_sec";
      agents = as_int s "agents";
      initial_position =
        as_enum s "initial_position" [ "domain_center" ];
      initial_heading =
        as_enum s "initial_heading" [ "uniform_0_2pi" ];
      boundary =
        as_enum s "boundary" [ "specular_reflect_recursive" ];
      record_initial = as_bool s "record_initial_frame";
    }
  in
  require_pos "dt_sec" c.dt;
  if c.agents <= 0 then
    failwith "common.agents must be > 0";
  if not c.record_initial then
    failwith "common.record_initial_frame must equal true";
  c

let model_section tbl d =
  section tbl ("model." ^ d.name)

let speed_params s =
  let m = as_float s "step_mean_um" in
  let sd = as_float s "step_sd_um" in
  require_pos "step_mean_um" m;
  require_nonneg "step_sd_um" sd;
  (m, sd)

let turn_param s key =
  let x = as_float s key in
  require_nonneg key x;
  x

let prob s key =
  let x = as_float s key in
  require_range key 0. 1. x;
  x


(* -------------------------------------------------------------------------- *)
(* Prepared model parameters                                                  *)
(* -------------------------------------------------------------------------- *)

(*
   [prepared] is the executable form of a validated model-specific TOML
   section. Parsing/validation is therefore completed once before the simulation
   loop rather than repeatedly at each time step.
*)
type prepared =
  | Basic of float * float * float
  | Ar1 of float * float * float * float * string
  | Ou of float * float * string
  | Coupled of string * float * float * float * float * float
  | Pause of float * float * float * float * float * string
  | Turn_switch of float * float * float * float * float
  | Speed_switch of float * float * float * float * float * float
  | Hetero2 of float * float * float
  | Hetero3 of float * float * float * float * float * float
  | Rev of float * float * float * float
  | Local of (float * float) array
  | Whole of (float * float) array array * string * string

type agent_state = {
  id : int;
  mutable x : float;
  mutable y : float;
  mutable heading : float;
  mutable vx : float;
  mutable vy : float;
  mutable prev_turn : float;
  mutable hidden_state : bool;
  mutable hits : int;
  trajectory_effect : float;
  whole_seq : (float * float) array option;
  whole_rot : float;
}

let prepare d tbl =
  let s = model_section tbl d in
  match d.kind with
  | Iid | Ballistic ->
      let m, sd = speed_params s in
      Basic (m, sd, 0.)

  | Pcrw ->
      let law =
        as_enum s "innovation_law"
          [ "gaussian"; "empirical_independent"; "empirical_joint" ]
      in
      if law <> "gaussian" then
        failwith
          "CAN-PCRW: frozen executable canonical form is gaussian; \
           empirical forms are represented by CAN-EMP-LOCAL";
      let m, sd = speed_params s in
      Basic (m, sd, turn_param s "turn_sd_rad")

  | Turn_ar1 ->
      let m, sd = speed_params s in
      let t = turn_param s "turn_sd_rad" in
      let r = as_float s "turn_memory" in
      require_open "turn_memory" (-1.) 1. r;
      Ar1
        ( m,
          sd,
          t,
          r,
          as_enum s "initial_turn" [ "zero"; "stationary_draw" ] )

  | Velocity_ou ->
      let r = as_float s "velocity_rho" in
      let n = as_float s "velocity_noise_um" in
      require_range "velocity_rho" 0. (1. -. epsilon_float) r;
      require_pos "velocity_noise_um" n;
      Ou
        ( r,
          n,
          as_enum s "initial_velocity" [ "zero"; "stationary_draw" ] )

  | Speed_turn ->
      let f =
        as_enum s "formula"
          [ "RUN2_additive_rad"; "RUN3_multiplicative" ]
      in
      let m, sd = speed_params s in
      if sd <= 0. then
        failwith "CAN-SPEED-TURN step_sd_um must be > 0";
      let floor =
        let x = as_float s "turn_scale_floor" in
        require_pos "turn_scale_floor" x;
        x
      in
      Coupled
        ( f,
          m,
          sd,
          turn_param s "turn_sd_rad",
          as_float s "coupling",
          floor )

  | Switch_pause ->
      let m, sd = speed_params s in
      Pause
        ( prob s "p_move_stay",
          prob s "p_pause_stay",
          m,
          sd,
          turn_param s "turn_sd_rad",
          as_enum s "pause_emission" [ "exact_zero"; "low_speed" ] )

  | Switch_turn ->
      ignore (as_enum s "transition_form" [ "symmetric_flip" ]);
      let m, sd = speed_params s in
      Turn_switch
        ( prob s "switch_prob",
          turn_param s "run_turn_sd_rad",
          turn_param s "reorient_turn_sd_rad",
          m,
          sd )

  | Switch_speed ->
      ignore (as_enum s "transition_form" [ "symmetric_flip" ]);
      let m, sd = speed_params s in
      let sf = as_float s "slow_factor" in
      let mn = as_float s "step_min_um" in
      require_range "slow_factor" 0. 1. sf;
      require_nonneg "step_min_um" mn;
      Speed_switch
        ( prob s "switch_prob",
          sf,
          mn,
          m,
          sd,
          turn_param s "turn_sd_rad" )

  | Het_speed ->
      let f =
        as_enum s "formula"
          [ "RUN2_additive_fixed"; "RUN3_multiplicative" ]
      in
      let m = as_float s "step_mean_um" in
      require_pos "step_mean_um" m;
      let t = turn_param s "turn_sd_rad" in
      if f = "RUN2_additive_fixed" then begin
        let h = as_float s "hetero_sd_um" in
        require_nonneg "hetero_sd_um" h;
        Hetero2 (m, h, t)
      end
      else begin
        let sd = as_float s "step_sd_um" in
        let mn = as_float s "step_min_um" in
        let cv = as_float s "hetero_cv" in
        let gm = as_float s "hetero_multiplier_min" in
        require_nonneg "step_sd_um" sd;
        require_nonneg "step_min_um" mn;
        require_nonneg "hetero_cv" cv;
        require_pos "hetero_multiplier_min" gm;
        Hetero3 (m, sd, mn, cv, gm, t)
      end

  | Reversal ->
      let m, sd = speed_params s in
      let a = as_float s "reversal_angle_rad" in
      if abs_float (a -. pi) > 1e-12 then
        failwith
          "reversal_angle_rad must equal structural pi";
      Rev
        ( m,
          sd,
          turn_param s "turn_sd_rad",
          prob s "reversal_prob" )

  | Emp_local ->
      ignore
        (as_enum s "conditioning" [ "iid_adjacent_pair" ]);
      Local
        (load_transitions
           (value s "training_transition_table_uri")
           (value s "training_transition_table_sha256"))

  | Emp_whole ->
      Whole
        ( load_library
            (value s "training_trajectory_library_uri")
            (value s "training_trajectory_library_sha256"),
          as_enum s "orientation_policy"
            [ "laboratory"; "random_rotation" ],
          as_enum s "post_sequence_policy"
            [ "stop"; "zero_steps"; "reject_length_mismatch" ] )


(* -------------------------------------------------------------------------- *)
(* Model execution                                                            *)
(* -------------------------------------------------------------------------- *)

(*
   Every canonical model enters the same execution function. Shared protocol
   settings are loaded once, model-specific parameters are prepared once, and
   only the local movement update differs inside the time loop.

   A run may contain any positive number of independent ABCA agents.
   Each agent carries its own dynamical state and, where applicable, its own
   trajectory-level random effect or empirical whole-trajectory draw.
   Initial positions can be placed at the domain centre or sampled uniformly
   over a disk using INIT=DISK (or the legacy alias INIT=CIRCLE) together with
   RADIUS=<value>.
*)
let run_for
    d
    ~rows
    ~cols
    ~generations
    ~seed
    ~density:_
    ~agents
    ~topology
    ~plugin_args
    ~output
  =
  reject_unknown_args plugin_args;

  if rows <= 0 || cols <= 0 then
    failwith "rows and cols must be positive";

  if generations < 0 then
    failwith "generations must be nonnegative";

  if topology <> Grid.Bounded then
    failwith
      "canonical portfolio requires bounded recursive specular reflection; \
       do not use --toroidal";

  let n_agents =
    match agents with
    | Some n when n > 0 -> n
    | Some _ -> failwith "--agents must be > 0"
    | None -> failwith "canonical portfolio requires an explicit --agents value"
  in

  let path = parameter_file plugin_args in
  let init = initialisation plugin_args in
  let tbl = load_toml path in
  validate_schema tbl;

  let common = load_common tbl in
  let p = prepare d tbl in
  let rng = Rng.create seed in

  (*
     [common.agents] is retained in the parameter file as part of the frozen
     single-trajectory specification used during reconciliation/fitting.
     Production simulations may request any positive number of independent
     ABCA agents through --agents; the actual value is recorded in metadata.
  *)

  let domain_cx = float_of_int cols /. 2. in
  let domain_cy = float_of_int rows /. 2. in

  (match init with
  | Init_center -> ()
  | Init_circle radius ->
      let max_radius = 0.5 *. float_of_int (min rows cols) in
      if radius >= max_radius then
        failwith
          (Printf.sprintf
             "RADIUS=%g does not fit strictly inside the %dx%d bounded domain"
             radius cols rows));

  let initial_xy () =
    match init with
    | Init_center -> (domain_cx, domain_cy)
    | Init_circle radius ->
        (* sqrt(U) gives a uniform spatial density over disk area. *)
        let r = radius *. sqrt (Rng.float rng 1.0) in
        let a = Rng.float rng (2. *. pi) in
        (domain_cx +. (r *. cos a), domain_cy +. (r *. sin a))
  in

  let initialise_agent id =
    let x0, y0 = initial_xy () in
    let heading0 = Rng.float rng (2. *. pi) in

    let prev_turn0, vx0, vy0 =
      match p with
      | Ar1 (_, _, sd, _, "stationary_draw") ->
          (sd *. normal rng, 0., 0.)
      | Ou (r, n, "stationary_draw") ->
          let sd = n /. sqrt (1. -. (r *. r)) in
          (0., sd *. normal rng, sd *. normal rng)
      | _ -> (0., 0., 0.)
    in

    let trajectory_effect =
      match p with
      | Hetero2 (m, h, _) ->
          max 0. (m +. (h *. normal rng))
      | Hetero3 (_, _, _, cv, gmin, _) ->
          max gmin (1. +. (cv *. normal rng))
      | _ -> 1.
    in

    let whole_seq, whole_rot =
      match p with
      | Whole (lib, orientation, policy) ->
          let seq = lib.(Rng.int rng (Array.length lib)) in
          if
            policy = "reject_length_mismatch"
            && Array.length seq <> generations
          then
            failwith
              "CAN-EMP-WHOLE source length does not match generations";
          let rot =
            if orientation = "random_rotation" then
              Rng.float rng (2. *. pi)
            else
              0.
          in
          (Some seq, rot)
      | _ -> (None, 0.)
    in

    {
      id;
      x = x0;
      y = y0;
      heading = heading0;
      vx = vx0;
      vy = vy0;
      prev_turn = prev_turn0;
      hidden_state = false;
      hits = 0;
      trajectory_effect;
      whole_seq;
      whole_rot;
    }
  in

  let states = Array.init n_agents initialise_agent in
  let n_frames = generations + 1 in

  (* Records are stored contiguously by agent, then by frame. *)
  let records =
    Array.make
      (n_agents * n_frames)
      {
        Abca_io.Agent_trace.frame = 0;
        id = 0;
        x = 0.;
        y = 0.;
        row = 0;
        col = 0;
        angle = 0;
        age = 0;
        state = 0;
      }
  in

  let record_index id frame = (id * n_frames) + frame in

  let store a frame st =
    records.(record_index a.id frame) <-
      {
        Abca_io.Agent_trace.frame = frame;
        id = a.id;
        x = a.x;
        y = a.y;
        row = clamp 0 (rows - 1) (int_of_float (floor a.y));
        col = clamp 0 (cols - 1) (int_of_float (floor a.x));
        angle = int_of_float (180. *. a.heading /. pi);
        age = frame;
        state = st;
      }
  in

  let move a speed turn =
    a.heading <- wrap_angle (a.heading +. turn);
    a.vx <- speed *. cos a.heading;
    a.vy <- speed *. sin a.heading;

    let xx, yy, hh, vxx, vyy, n =
      apply_boundary
        rows
        cols
        (a.x +. a.vx)
        (a.y +. a.vy)
        a.heading
        a.vx
        a.vy
    in
    a.x <- xx;
    a.y <- yy;
    a.heading <- hh;
    a.vx <- vxx;
    a.vy <- vyy;
    a.hits <- a.hits + n
  in

  let update_agent a frame =
    match p with
    | Basic (m, sd, t) ->
        if d.kind = Iid then
          a.heading <- Rng.float rng (2. *. pi);
        let speed = max 0. (m +. (sd *. normal rng)) in
        if d.kind = Iid then
          move a speed 0.
        else
          move a speed
            (if d.kind = Ballistic then 0. else t *. normal rng);
        0

    | Ar1 (m, sd, t, r, _) ->
        let speed = max 0. (m +. (sd *. normal rng)) in
        let turn =
          (r *. a.prev_turn)
          +. (sqrt (1. -. (r *. r)) *. t *. normal rng)
        in
        a.prev_turn <- turn;
        move a speed turn;
        0

    | Ou (r, n, _) ->
        let nvx = (r *. a.vx) +. (n *. normal rng) in
        let nvy = (r *. a.vy) +. (n *. normal rng) in
        let speed = sqrt ((nvx *. nvx) +. (nvy *. nvy)) in
        let h = if speed = 0. then a.heading else atan2 nvy nvx in
        a.heading <- h;
        a.vx <- nvx;
        a.vy <- nvy;

        let xx, yy, hh, vxx, vyy, k =
          apply_boundary
            rows
            cols
            (a.x +. nvx)
            (a.y +. nvy)
            h
            nvx
            nvy
        in
        a.x <- xx;
        a.y <- yy;
        a.heading <- hh;
        a.vx <- vxx;
        a.vy <- vyy;
        a.hits <- a.hits + k;
        0

    | Coupled (form, m, sd, t, c, floorv) ->
        let speed = max 0. (m +. (sd *. normal rng)) in
        let scale =
          if form = "RUN2_additive_rad" then
            max floorv (t +. (c *. (speed -. m)))
          else
            t
            *. max floorv
                 (1. +. (c *. (m -. speed) /. m))
        in
        move a speed (scale *. normal rng);
        0

    | Pause (pm, pp, m, sd, t, emission) ->
        let u = Rng.float rng 1. in
        a.hidden_state <-
          if a.hidden_state then
            u < pp
          else
            not (u < pm);

        if a.hidden_state then begin
          if emission = "low_speed" then
            failwith
              "CAN-SWITCH-PAUSE low_speed emission is unresolved in \
               frozen equation; select exact_zero"
        end
        else
          move a
            (max 0. (m +. (sd *. normal rng)))
            (t *. normal rng);

        if a.hidden_state then 1 else 0

    | Turn_switch (q, tr, te, m, sd) ->
        if Rng.float rng 1. < q then
          a.hidden_state <- not a.hidden_state;

        let turn =
          (if a.hidden_state then te else tr) *. normal rng
        in
        let speed = max 0. (m +. (sd *. normal rng)) in
        move a speed turn;
        if a.hidden_state then 1 else 0

    | Speed_switch (q, sf, smin, m, sd, t) ->
        if Rng.float rng 1. < q then
          a.hidden_state <- not a.hidden_state;

        let speed =
          max smin (m +. (sd *. normal rng))
          *. if a.hidden_state then sf else 1.
        in
        move a speed (t *. normal rng);
        if a.hidden_state then 1 else 0

    | Hetero2 (_, _, t) ->
        move a a.trajectory_effect (t *. normal rng);
        0

    | Hetero3 (m, sd, smin, _, _, t) ->
        move a
          (a.trajectory_effect *. max smin (m +. (sd *. normal rng)))
          (t *. normal rng);
        0

    | Rev (m, sd, t, pr) ->
        let speed = max 0. (m +. (sd *. normal rng)) in
        let turn =
          (t *. normal rng)
          +. if Rng.float rng 1. < pr then pi else 0.
        in
        move a speed turn;
        0

    | Local table ->
        let speed, turn =
          table.(Rng.int rng (Array.length table))
        in
        move a speed turn;
        0

    | Whole (_, _, policy) ->
        let seq = Option.get a.whole_seq in
        if frame - 1 < Array.length seq then begin
          let dx, dy = seq.(frame - 1) in
          let c = cos a.whole_rot in
          let s = sin a.whole_rot in
          let dx', dy' =
            ((dx *. c) -. (dy *. s), (dx *. s) +. (dy *. c))
          in
          let speed = sqrt ((dx' *. dx') +. (dy' *. dy')) in
          let h = if speed = 0. then a.heading else atan2 dy' dx' in
          a.heading <- h;
          a.vx <- dx';
          a.vy <- dy';

          let xx, yy, hh, vxx, vyy, k =
            apply_boundary
              rows
              cols
              (a.x +. dx')
              (a.y +. dy')
              h
              dx'
              dy'
          in
          a.x <- xx;
          a.y <- yy;
          a.heading <- hh;
          a.vx <- vxx;
          a.vy <- vyy;
          a.hits <- a.hits + k
        end
        else if policy = "stop" then
          ()
        else
          ();
        0
  in

  Array.iter (fun a -> store a 0 0) states;

  for frame = 1 to generations do
    Array.iter
      (fun a ->
        let st = update_agent a frame in
        store a frame st)
      states
  done;

  Array.iter
    (fun r ->
      if
        not
          (finite r.Abca_io.Agent_trace.x
          && finite r.y)
      then
        failwith "non-finite trajectory")
    records;

  let frames =
    Array.init
      n_frames
      (fun _ ->
        Array.init rows (fun _ -> Array.make cols 0))
  in

  Array.iter
    (fun r ->
      frames.(r.Abca_io.Agent_trace.frame).(r.row).(r.col) <- 1)
    records;

  let total_hits =
    Array.fold_left (fun acc a -> acc + a.hits) 0 states
  in

  let init_name, init_radius =
    match init with
    | Init_center -> ("CENTER", "NA")
    | Init_circle r -> ("DISK", string_of_float r)
  in

  let metadata =
    Abca_io.Metadata.of_list
      [
        ("model", d.name);
        ("family", "reconciled-canonical-portfolio");
        ("provenance", d.provenance);
        ("seed", string_of_int seed);
        ("rng", "OCaml Random.State seeded stream; Box-Muller normals");
        ("dt_sec", string_of_float common.dt);
        ("position_units", "micron");
        ("time_units", "second");
        ("boundary", common.boundary);
        ("boundary_hits", string_of_int total_hits);
        ("parameter_file", path);
        ("parameter_file_sha256", sha256_file path);
        ("parameter_file_agents", string_of_int common.agents);
        ("agents", string_of_int n_agents);
        ("initialisation", init_name);
        ("initialisation_radius", init_radius);
        ("generations_semantics", "n_observations_minus_1");
        ("trajectory_records", string_of_int (n_agents * n_frames));
      ]
  in

  let archive =
    Abca_io.Binary.make_archive
      ~rows
      ~cols
      ~generation:generations
      ~metadata
      ~frames
      ~agents:records
      ()
  in

  Abca_io.Binary.save
    ~filename:output
    ~archive
    ~codec:(module Codec)


(* -------------------------------------------------------------------------- *)
(* Export and ABCA registration                                               *)
(* -------------------------------------------------------------------------- *)

let export_xml ~input ~output =
  let a =
    Abca_io.Binary.load
      ~filename:input
      ~codec:(module Codec)
  in

  if Array.length a.agents > 0 then
    Abca_io.Xml.save_agent_trace_trackmate
      ~filename:output
      a.agents
  else
    let grid =
      Grid.create
        ~rows:a.header.rows
        ~cols:a.header.cols
        ()
    in
    Abca_io.Xml.save_frames
      ~filename:output
      ~model:"canonical-portfolio"
      ~grid
      ~generation:a.header.generation
      ~frames:a.frames
      ~codec:(module Xml_codec)

let make d =
  {
    Abca_models.Model.name = d.name;
    family = Abca_models.Model.Biological;
    kind = Abca_models.Model.Agent_based_model;
    description = d.label ^ " [" ^ d.provenance ^ "]";
    run = run_for d;
    export_xml;
    state_count = 2;
    to_color_index = (function
      | 0 -> None
      | x -> Some x);
  }

(* Public plugin entry point: expose all 13 canonical modes to ABCA. *)
let models =
  List.map make defs
