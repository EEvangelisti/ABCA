open Abca

(*
   Ballistic_angular_jitter_c3 — single-model ABCA plugin.

   The step length is max(0, N(step_mean_um, step_sd_um^2)), except that
   step_sd_um=0 produces the mean exactly without consuming a random draw.
   The angular increment is N(0, sigma_theta_rad_per_step^2) conditioned on
   [-3 sigma, +3 sigma]; sigma=0 likewise consumes no random draw.

   Simulation and XML export conventions are retained from the original plugin:
   bounded specular reflection, optional disk initialisation, one record for
   frame zero and one per generation, and external TOML parameters.
*)

let model_name = "C3-CAN-BALLISTIC-ANGULAR-JITTER-01"
let model_label =
  "ballistic motion with per-generation truncated-normal angular jitter"
let model_provenance = "CAN-BALLISTIC; mathematician proposal cycle 3"

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

   The model-specific parameter checks below validate the only model retained.
   Other model sections in a legacy portfolio TOML are ignored.
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
               let k, v = split_once '=' line in
               if k = "" then failwith "parameter file: empty key";
               if !section = "" then begin
                 (* The fitting pipeline writes one TOML document-level
                    metadata key before the first section. Keep it outside
                    the section schema, but validate it explicitly. *)
                 if k = "schema_version" then begin
                   let v = unquote v in
                   if v <> "canonical-portfolio-parameters-1.0" then
                     failwith
                       ("parameter file: unsupported schema_version " ^ v)
                 end
                 else
                   failwith
                     ("parameter file: unsupported top-level key " ^ k)
               end
               else
                 add k (unquote v)
             end
         done
       with End_of_file -> ());

      List.rev_map
        (fun (name, entries) -> (name, List.rev entries))
        !acc)


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

let require_nonneg key x =
  if x < 0. then failwith (key ^ " must be >= 0")

let require_pos key x =
  if x <= 0. then failwith (key ^ " must be > 0")


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

(* Exact N(0,sigma^2) conditional on [-3 sigma,+3 sigma].  The sigma=0
   branch consumes no random numbers, guaranteeing exact parent recovery. *)
let truncated_normal_3sigma rng sigma =
  if sigma = 0. then 0.
  else
    let rec draw () =
      let x = sigma *. normal rng in
      if x >= -. (3. *. sigma) && x <= 3. *. sigma then x else draw ()
    in
    draw ()

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
(* Parameter-file checksum                                                  *)
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

let model_section tbl =
  section tbl ("model." ^ model_name)

let speed_params s =
  let m = as_float s "step_mean_um" in
  let sd = as_float s "step_sd_um" in
  require_pos "step_mean_um" m;
  require_nonneg "step_sd_um" sd;
  (m, sd)

(* -------------------------------------------------------------------------- *)
(* Ballistic_angular_jitter_c3 parameters and state                           *)
(* -------------------------------------------------------------------------- *)

type parameters = {
  step_mean_um : float;
  step_sd_um : float;
  sigma_theta_rad_per_step : float;
}

(* Validate only the sections used by C3, while remaining compatible with a
   legacy TOML also containing parameters for unrelated portfolio models. *)
let check_keys section_name entries allowed =
  List.iter
    (fun (k, _) ->
      if not (List.mem k allowed) then
        failwith
          ("unsupported key in [" ^ section_name ^ "]: " ^ k))
    entries

let prepare tbl =
  let common_keys =
    [ "dt_sec"; "agents"; "initial_position"; "initial_heading";
      "boundary"; "record_initial_frame" ]
  in
  check_keys "common" (section tbl "common") common_keys;
  let s = model_section tbl in
  check_keys ("model." ^ model_name) s
    [ "step_mean_um"; "step_sd_um"; "sigma_theta_rad_per_step" ];
  let step_mean_um, step_sd_um = speed_params s in
  let sigma_theta_rad_per_step = as_float s "sigma_theta_rad_per_step" in
  require_nonneg "sigma_theta_rad_per_step" sigma_theta_rad_per_step;
  { step_mean_um; step_sd_um; sigma_theta_rad_per_step }

type agent_state = {
  id : int;
  mutable x : float;
  mutable y : float;
  mutable heading : float;
  mutable hits : int;
}

(* -------------------------------------------------------------------------- *)
(* Model execution                                                            *)
(* -------------------------------------------------------------------------- *)

let run
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
      "C3 model requires bounded recursive specular reflection; \
       do not use --toroidal";

  let n_agents =
    match agents with
    | Some n when n > 0 -> n
    | Some _ -> failwith "--agents must be > 0"
    | None -> failwith "C3 model requires an explicit --agents value"
  in

  let path = parameter_file plugin_args in
  let init = initialisation plugin_args in
  let tbl = load_toml path in
  let common = load_common tbl in
  let p = prepare tbl in
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
    { id; x = x0; y = y0; heading = heading0; hits = 0 }
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
    let vx = speed *. cos a.heading in
    let vy = speed *. sin a.heading in
    let xx, yy, hh, _, _, n =
      apply_boundary
        rows cols
        (a.x +. vx) (a.y +. vy)
        a.heading vx vy
    in
    a.x <- xx;
    a.y <- yy;
    a.heading <- hh;
    a.hits <- a.hits + n
  in

  let update_agent a =
    (* One ABCA generation is one step; dt_sec is metadata and does not
       rescale sigma or the unchanged parent step-length distribution. *)
    let speed =
      if p.step_sd_um = 0. then p.step_mean_um
      else max 0. (p.step_mean_um +. (p.step_sd_um *. normal rng))
    in
    move a speed (truncated_normal_3sigma rng p.sigma_theta_rad_per_step)
  in

  Array.iter (fun a -> store a 0 0) states;

  for frame = 1 to generations do
    Array.iter
      (fun a ->
        update_agent a;
        store a frame 0)
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
        ("model", model_name);
        ("family", "zoospore-ballistic-angular-jitter");
        ("provenance", model_provenance);
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
      ~model:model_name
      ~grid
      ~generation:a.header.generation
      ~frames:a.frames
      ~codec:(module Xml_codec)

(* ABCA requires a list of registered models even for a single-model plugin. *)
let models =
  [
    {
      Abca_models.Model.name = model_name;
      family = Abca_models.Model.Biological;
      kind = Abca_models.Model.Agent_based_model;
      description = model_label ^ " [" ^ model_provenance ^ "]";
      run;
      export_xml;
      state_count = 2;
      to_color_index = (function
        | 0 -> None
        | x -> Some x);
    }
  ]
