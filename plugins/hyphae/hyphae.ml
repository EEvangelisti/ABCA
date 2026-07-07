(*
   ABCA hyphae plugin.

   Local-rule principle
   --------------------
   The dense grid stores deposited hyphal material.
   The sparse list of agents stores only active apices.

   At each generation, each apex decides locally:
   - whether it elongates;
   - whether it branches;
   - which nearby forward cell it can occupy;
   - whether local congestion inhibits branching.

   No rule uses global morphology, total colony size, distance to the colony edge,
   or any future state. Global patterns therefore emerge from local tip decisions.
*)

open Abca

type state = int

(* 0 = empty; 1 = active apex / youngest hypha; >1 = older deposited hypha. *)

type init_shape =
  | Init_point
  | Init_line
  | Init_disk
  | Init_radial

type params = {
  growth_prob : float;
  branch_prob : float;
  branch_age : int;
  dirs : int;
  wiggle : int;
  branch_angle : int;
  branch_jitter : int;
  branch_distance : int;
  congestion : int;
  max_age : int;
  apices : int;
  init_shape : init_shape;
  radius : float;
  seed : int;
}

type rule_def = {
  id : string;
  label : string;
  growth_prob : float;
  branch_prob : float;
  branch_age : int;
  dirs : int;
  wiggle : int;
  branch_angle : int;
  branch_jitter : int;
  branch_distance : int;
  congestion : int;
  max_age : int;
  apices : int;
  init_shape : init_shape;
  radius : float;
}

type apex = {
  id : int;
  row : int;
  col : int;
  age : int;
  angle : int;
}

let rules_file = Filename.concat "plugins/hyphae" "hyphae.rules"

module Binary_codec = struct
  type t = state
  let to_int32 = Int32.of_int
  let of_int32 = Int32.to_int
end

module Xml_codec = struct
  type t = state
  let to_string = string_of_int
end

let to_color_index x = x
let clamp lo hi x = max lo (min hi x)
let trim = String.trim

let normalize_angle dirs angle =
  ((angle mod dirs) + dirs) mod dirs

let random_signed rng amplitude =
  if amplitude <= 0 then 0
  else Rng.range_int rng ~min:(-amplitude) ~max:amplitude

let angle_to_offset dirs angle =
  let theta = 2.0 *. Float.pi *. float_of_int angle /. float_of_int dirs in
  let dr = int_of_float (Float.round (sin theta)) in
  let dc = int_of_float (Float.round (cos theta)) in
  if dr = 0 && dc = 0 then (0, 1) else (dr, dc)

let coord row col = { Grid.row; col }

let normalize_target grid row col =
  Grid.normalize grid (coord row col)

let empty_frame grid =
  Array.init (Grid.rows grid) (fun _ -> Array.make (Grid.cols grid) 0)

let copy_frame frame = Array.map Array.copy frame

let state_of_age max_age age =
  1 + clamp 0 max_age age

let occupied frame row col =
  row >= 0 && row < Array.length frame &&
  col >= 0 && col < Array.length frame.(row) &&
  frame.(row).(col) <> 0

let set_hypha (params : params) frame row col age =
  frame.(row).(col) <- state_of_age params.max_age age

let moore_offsets =
  [| (-1,-1); (-1,0); (-1,1);
     ( 0,-1);         ( 0,1);
     ( 1,-1); ( 1,0); ( 1,1) |]

let neighbour_count grid frame row col =
  Array.fold_left
    (fun acc (dr, dc) ->
       match normalize_target grid (row + dr) (col + dc) with
       | None -> acc
       | Some p -> if frame.(p.Grid.row).(p.col) <> 0 then acc + 1 else acc)
    0 moore_offsets

let congested (params : params) grid frame row col =
  params.congestion > 0 && neighbour_count grid frame row col >= params.congestion

let ordered_deviations radius =
  let rec loop k acc =
    if k > radius then List.rev acc
    else loop (k + 1) (k :: (-k) :: acc)
  in
  0 :: loop 1 []

let candidate_angles (params : params) angle =
  let radius = max 1 (params.wiggle + 2) in
  ordered_deviations radius
  |> List.map (fun d -> normalize_angle params.dirs (angle + d))

let find_growth_target (params : params) grid old_frame reserved apex angle =
  let rec loop = function
    | [] -> None
    | a :: rest ->
        let dr, dc = angle_to_offset params.dirs a in
        begin match normalize_target grid (apex.row + dr) (apex.col + dc) with
        | None -> loop rest
        | Some p ->
            let key = (p.Grid.row, p.col) in
            if old_frame.(p.Grid.row).(p.col) = 0 && not (Hashtbl.mem reserved key)
            then Some (p.Grid.row, p.col, a)
            else loop rest
        end
  in
  loop (candidate_angles params angle)

let branching_probability (params : params) age =
  let distance_factor =
    if params.branch_distance <= 0 then 1.0
    else min 1.0 (float_of_int age /. float_of_int params.branch_distance)
  in
  params.branch_prob *. distance_factor

let branch_angle rng (params : params) angle =
  let side = if Rng.bool rng then params.branch_angle else -params.branch_angle in
  normalize_angle params.dirs (angle + side + random_signed rng params.branch_jitter)

let try_branch rng (params : params) grid old_frame new_frame reserved next_id apex angle age acc =
  if age < params.branch_age || congested params grid old_frame apex.row apex.col then
    next_id, acc, age
  else if not (Rng.chance rng (branching_probability params age)) then
    next_id, acc, age
  else
    let bangle = branch_angle rng params angle in
    let dr, dc = angle_to_offset params.dirs bangle in
    match normalize_target grid (apex.row + dr) (apex.col + dc) with
    | None -> next_id, acc, age
    | Some p ->
        let key = (p.Grid.row, p.col) in
        if old_frame.(p.Grid.row).(p.col) <> 0 || Hashtbl.mem reserved key then
          next_id, acc, age
        else begin
          Hashtbl.replace reserved key next_id;
          set_hypha params new_frame p.Grid.row p.col 0;
          let child = { id = next_id; row = p.Grid.row; col = p.col; age = 0; angle = bangle } in
          next_id + 1, child :: acc, 0
        end

let step_apex rng (params : params) grid old_frame new_frame reserved next_id acc apex =
  let age = min params.max_age (apex.age + 1) in
  let angle = normalize_angle params.dirs (apex.angle + random_signed rng params.wiggle) in
  let next_id, acc, age =
    try_branch rng params grid old_frame new_frame reserved next_id apex angle age acc
  in
  if Rng.chance rng params.growth_prob then begin
    set_hypha params new_frame apex.row apex.col age;
    match find_growth_target params grid old_frame reserved apex angle with
    | None -> next_id, acc
    | Some (row, col, angle) ->
        Hashtbl.replace reserved (row, col) apex.id;
        set_hypha params new_frame row col 0;
        next_id, { apex with row; col; age; angle } :: acc
  end else begin
    Hashtbl.replace reserved (apex.row, apex.col) apex.id;
    set_hypha params new_frame apex.row apex.col age;
    next_id, { apex with age; angle } :: acc
  end

let trace_record generation apex : Abca_io.Agent_trace.record = {
  frame = generation;
  id = apex.id;
  x = float_of_int apex.col +. 0.5;
  y = float_of_int apex.row +. 0.5;
  row = apex.row;
  col = apex.col;
  angle = apex.angle;
  age = apex.age;
  state = 1;
}

let initial_apices params grid =
  let rng = Rng.create params.seed in
  let rows = Grid.rows grid in
  let cols = Grid.cols grid in
  let cr = rows / 2 in
  let cc = cols / 2 in
  let make id row col angle =
    let p = match normalize_target grid row col with Some p -> p | None -> coord cr cc in
    { id; row = p.Grid.row; col = p.col; age = 0; angle = normalize_angle params.dirs angle }
  in
  match params.init_shape with
  | Init_point ->
      Array.init params.apices (fun id -> make id cr cc (Rng.int rng params.dirs))
  | Init_radial ->
      Array.init params.apices (fun id ->
        let angle = (id * params.dirs) / max 1 params.apices in
        make id cr cc angle)
  | Init_line ->
      Array.init params.apices (fun id ->
        let span = max 1 (params.apices - 1) in
        let row = cr - params.apices / 2 + id in
        let angle = if id mod 2 = 0 then 0 else params.dirs / 2 in
        ignore span;
        make id row cc angle)
  | Init_disk ->
      Array.init params.apices (fun id ->
        let rec sample attempts =
          if attempts <= 0 then cr, cc
          else
            let r = cr + Rng.range_int rng ~min:(-int_of_float params.radius) ~max:(int_of_float params.radius) in
            let c = cc + Rng.range_int rng ~min:(-int_of_float params.radius) ~max:(int_of_float params.radius) in
            let d2 = float_of_int ((r - cr) * (r - cr) + (c - cc) * (c - cc)) in
            if d2 <= params.radius *. params.radius then r, c else sample (attempts - 1)
        in
        let row, col = sample 200 in
        make id row col (Rng.int rng params.dirs))

let frame_of_initial_apices (params : params) grid apices =
  let frame = empty_frame grid in
  Array.iter (fun a -> set_hypha params frame a.row a.col 0) apices;
  frame

let simulate params grid generations =
  let rng = Rng.create params.seed in
  let frames = Array.make (generations + 1) [||] in
  let trace = ref [] in
  let apices = ref (Array.to_list (initial_apices params grid)) in
  let next_id = ref params.apices in
  let record generation =
    List.iter (fun a -> trace := trace_record generation a :: !trace) !apices
  in
  frames.(0) <- frame_of_initial_apices params grid (Array.of_list !apices);
  record 0;
  for generation = 1 to generations do
    let old_frame = frames.(generation - 1) in
    let new_frame = copy_frame old_frame in
    let reserved = Hashtbl.create (2 * max 1 (List.length !apices)) in
    let nid, new_apices =
      List.fold_left
        (fun (nid, acc) a -> step_apex rng params grid old_frame new_frame reserved nid acc a)
        (!next_id, [])
        !apices
    in
    next_id := nid;
    apices := List.rev new_apices;
    frames.(generation) <- new_frame;
    record generation
  done;
  frames, Array.of_list (List.rev !trace)

let split_tokens s =
  s |> String.split_on_char '/' |> List.map trim |> List.filter ((<>) "")

let split_key_value token =
  match String.split_on_char '=' token with
  | [ key; value ] -> String.uppercase_ascii (trim key), trim value
  | _ -> failwith ("Hyphae: invalid token: " ^ token)

let get_string key default table =
  match List.assoc_opt key table with Some x -> x | None -> default

let get_int key default table =
  get_string key (string_of_int default) table |> int_of_string

let get_float key default table =
  get_string key (string_of_float default) table |> float_of_string

let parse_init_shape s =
  match String.uppercase_ascii (trim s) with
  | "POINT" -> Init_point
  | "LINE" -> Init_line
  | "DISK" -> Init_disk
  | "RADIAL" -> Init_radial
  | other -> failwith ("Hyphae: unknown INIT shape: " ^ other)

let string_of_init_shape = function
  | Init_point -> "point"
  | Init_line -> "line"
  | Init_disk -> "disk"
  | Init_radial -> "radial"

let slugify s =
  s |> String.lowercase_ascii |> String.map (function ' ' | '_' -> '-' | c -> c)

let parse_rule_line line =
  let line = trim line in
  if line = "" || line.[0] = '#' then None
  else
    Scanf.sscanf line "AUTOMATON %S: %[^\n]" (fun label body ->
      let table = body |> split_tokens |> List.map split_key_value in
      Some {
        id = slugify label;
        label;
        growth_prob = get_float "GROWTH" 0.95 table;
        branch_prob = get_float "BRANCH" 0.04 table;
        branch_age = get_int "AGE" 10 table;
        dirs = get_int "DIRS" 64 table;
        wiggle = get_int "WIGGLE" 4 table;
        branch_angle = get_int "ANGLE" 12 table;
        branch_jitter = get_int "JITTER" 8 table;
        branch_distance = get_int "DISTANCE" 16 table;
        congestion = get_int "CONGESTION" 5 table;
        max_age = get_int "MAX_AGE" 180 table;
        apices = get_int "APICES" 1 table;
        init_shape = parse_init_shape (get_string "INIT" "POINT" table);
        radius = get_float "RADIUS" 6.0 table;
      })

let read_lines filename =
  let ic = open_in filename in
  Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () ->
    let rec loop acc =
      match input_line ic with
      | line -> loop (line :: acc)
      | exception End_of_file -> List.rev acc
    in
    loop [])

let load_rules filename =
  read_lines filename |> List.filter_map parse_rule_line

let find_arg key plugin_args =
  List.assoc_opt (String.uppercase_ascii key) plugin_args

let override_int key current plugin_args =
  match find_arg key plugin_args with None -> current | Some s -> int_of_string s

let override_float key current plugin_args =
  match find_arg key plugin_args with None -> current | Some s -> float_of_string s

let override_init key current plugin_args =
  match find_arg key plugin_args with None -> current | Some s -> parse_init_shape s

let apply_plugin_args plugin_args (p : params) = {
  p with
  growth_prob = override_float "GROWTH" p.growth_prob plugin_args;
  branch_prob = override_float "BRANCH" p.branch_prob plugin_args;
  branch_age = override_int "AGE" p.branch_age plugin_args;
  dirs = override_int "DIRS" p.dirs plugin_args;
  wiggle = override_int "WIGGLE" p.wiggle plugin_args;
  branch_angle = override_int "ANGLE" p.branch_angle plugin_args;
  branch_jitter = override_int "JITTER" p.branch_jitter plugin_args;
  branch_distance = override_int "DISTANCE" p.branch_distance plugin_args;
  congestion = override_int "CONGESTION" p.congestion plugin_args;
  max_age = override_int "MAX_AGE" p.max_age plugin_args;
  apices = override_int "APICES" p.apices plugin_args;
  init_shape = override_init "INIT" p.init_shape plugin_args;
  radius = override_float "RADIUS" p.radius plugin_args;
}

let metadata (rule_def : rule_def) (params : params) ~rows ~cols ~generations ~seed ~density ~topology =
  Abca_io.Metadata.of_list [
    "model", rule_def.id;
    "family", "biological";
    "kind", "hybrid";
    "rows", string_of_int rows;
    "cols", string_of_int cols;
    "generations", string_of_int generations;
    "seed", string_of_int seed;
    "density", string_of_float density;
    "topology", (match topology with Grid.Bounded -> "bounded" | Grid.Toroidal -> "toroidal");
    "growth", string_of_float params.growth_prob;
    "branch", string_of_float params.branch_prob;
    "age", string_of_int params.branch_age;
    "dirs", string_of_int params.dirs;
    "wiggle", string_of_int params.wiggle;
    "angle", string_of_int params.branch_angle;
    "jitter", string_of_int params.branch_jitter;
    "distance", string_of_int params.branch_distance;
    "congestion", string_of_int params.congestion;
    "max_age", string_of_int params.max_age;
    "apices", string_of_int params.apices;
    "init", string_of_init_shape params.init_shape;
    "radius", string_of_float params.radius;
  ]

let params_of_rule (rule_def : rule_def) ~seed ~agents = {
  seed;
  growth_prob = rule_def.growth_prob;
  branch_prob = rule_def.branch_prob;
  branch_age = rule_def.branch_age;
  dirs = max 8 rule_def.dirs;
  wiggle = rule_def.wiggle;
  branch_angle = rule_def.branch_angle;
  branch_jitter = rule_def.branch_jitter;
  branch_distance = rule_def.branch_distance;
  congestion = rule_def.congestion;
  max_age = max 1 (min 254 rule_def.max_age);
  apices = (match agents with Some n -> n | None -> rule_def.apices);
  init_shape = rule_def.init_shape;
  radius = rule_def.radius;
}

let run_for (rule_def : rule_def) ~rows ~cols ~generations ~seed ~density ~agents ~topology ~plugin_args ~output =
  let params = params_of_rule rule_def ~seed ~agents |> apply_plugin_args plugin_args in
  let grid = Grid.create ~topology ~rows ~cols () in
  let frames, agents_trace = simulate params grid generations in
  let metadata = metadata rule_def params ~rows ~cols ~generations ~seed ~density ~topology in
  let archive = Abca_io.Binary.make_archive ~rows ~cols ~generation:generations ~metadata ~frames ~agents:agents_trace () in
  Abca_io.Binary.save ~filename:output ~archive ~codec:(module Binary_codec)

let export_xml_for _rule_def ~input ~output =
  let open Abca_io.Binary in
  let { header; frames; _ } = load ~filename:input ~codec:(module Binary_codec) in
  let grid = Grid.create ~rows:header.rows ~cols:header.cols () in
  Abca_io.Xml.save_frames ~filename:output ~model:"hyphae" ~grid ~generation:header.generation ~frames ~codec:(module Xml_codec)

let description rule_def =
  Printf.sprintf "%s hyphal model: local tip growth, branch=%.3f, init=%s, apices=%d"
    rule_def.label rule_def.branch_prob (string_of_init_shape rule_def.init_shape) rule_def.apices

let make_model (rule_def : rule_def) = {
  Abca_models.Model.name = rule_def.id;
  family = Abca_models.Model.Biological;
  kind = Abca_models.Model.Hybrid_model;
  description = description rule_def;
  state_count = rule_def.max_age + 2;
  to_color_index;
  run = run_for rule_def;
  export_xml = export_xml_for rule_def;
}

let models = load_rules rules_file |> List.map make_model
