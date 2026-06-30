(*
 * ABCA (Agent-Based Cellular Automata)
 * A modular simulation framework for discrete spatial systems,
 * ranging from classical cellular automata to biologically inspired
 * agent-based models.
 *
 * Copyright (c) 2026 Edouard Evangelisti
 *
 * Distributed under the MIT License.
 * This software is provided "as is", without warranty of any kind.
 * See the LICENSE file for details.
 *)

open Abca

type state = int
(* 0 = empty; >0 = zoospore, optionally aged *)

type init_shape =
  | Init_full
  | Init_disk
  | Init_ring

type params = {
  dirs        : int;
  base_step   : int;
  fast_step   : int;
  fast_prob   : float;
  wiggle      : int;
  persistence : int;
  min_turn    : int;
  max_age     : int;
  agents      : int;
  init_shape  : init_shape;
  radius      : float;
  thickness   : float;
  seed        : int;
}

type rule_def = {
  id          : string;
  label       : string;
  dirs        : int;
  base_step   : int;
  fast_step   : int;
  fast_prob   : float;
  wiggle      : int;
  persistence : int;
  min_turn    : int;
  max_age     : int;
  agents      : int;
  init_shape  : init_shape;
  radius      : float;
  thickness   : float;
}

type agent = {
  id    : int;
  row   : int;
  col   : int;
  age   : int;
  angle : int;
}

let state_of_agent (params : params) (ag : agent) = 1 + min ag.age params.max_age

let trace_record (params : params) frame (ag : agent) : Abca_io.Agent_trace.record =
  {
    frame;
    id = ag.id;
    row = ag.row;
    col = ag.col;
    age = ag.age;
    angle = ag.angle;
    state = state_of_agent params ag;
  }

let rules_file =
  Filename.concat "plugins/zoospores" "zoospores.rules"

let trim =
  String.trim

let slugify s =
  s
  |> String.lowercase_ascii
  |> String.map (function
      | ' ' | '_' -> '-'
      | c -> c)

let read_lines filename =
  let ic = open_in filename in
  Fun.protect
    ~finally:(fun () -> close_in_noerr ic)
    (fun () ->
       let rec loop acc =
         match input_line ic with
         | line -> loop (line :: acc)
         | exception End_of_file -> List.rev acc
       in
       loop [])

let split_tokens s =
  s
  |> String.split_on_char '/'
  |> List.map trim
  |> List.filter (fun x -> x <> "")

let split_key_value token =
  match String.split_on_char '=' token with
  | [ key; value ] ->
      String.uppercase_ascii (trim key), trim value
  | _ ->
      failwith ("Zoospore: invalid token: " ^ token)

let get_string key default table =
  match List.assoc_opt key table with
  | Some x -> x
  | None -> default

let get_int key default table =
  get_string key (string_of_int default) table
  |> int_of_string

let get_float key default table =
  get_string key (string_of_float default) table
  |> float_of_string

let parse_init_shape s =
  match String.uppercase_ascii (trim s) with
  | "FULL" | "RANDOM" -> Init_full
  | "DISK" | "CIRCLE" -> Init_disk
  | "RING" -> Init_ring
  | other ->
      failwith ("Zoospore: unknown INIT shape: " ^ other)

let string_of_init_shape = function
  | Init_full -> "full"
  | Init_disk -> "disk"
  | Init_ring -> "ring"

let parse_rule_line line =
  let line =
    trim line
  in

  if line = "" || line.[0] = '#' then
    None
  else
    try
      Scanf.sscanf line
        "AUTOMATON %S: %[^\n]"
        (fun label body ->
           let table =
             body
             |> split_tokens
             |> List.map split_key_value
           in

           let dirs =
             get_int "DIRS" 360 table
           in

           let base_step =
             get_int "BASE_STEP" 2 table
           in

           let fast_step =
             get_int "FAST_STEP" 5 table
           in

           let fast_prob =
             get_float "FAST_PROB" 0.166667 table
           in

           let wiggle =
             get_int "WIGGLE" 5 table
           in

           let persistence =
             get_int "PERSISTENCE" 12 table
           in

           let min_turn =
             get_int "MIN_TURN" 30 table
           in

           let max_age =
             get_int "MAX_AGE" 8 table
           in

           let agents =
             get_int "AGENTS" 200 table
           in

           let init_shape =
             parse_init_shape (get_string "INIT" "RING" table)
           in

           let radius =
             get_float "RADIUS" 60.0 table
           in

           let thickness =
             get_float "THICKNESS" 4.0 table
           in

           Some {
             id = slugify label;
             label;
             dirs;
             base_step;
             fast_step;
             fast_prob;
             wiggle;
             persistence;
             min_turn;
             max_age;
             agents;
             init_shape;
             radius;
             thickness;
           })
    with _ ->
      failwith ("Zoospore: cannot parse rule line: " ^ line)

let load_rules filename =
  read_lines filename
  |> List.filter_map parse_rule_line

module Binary_codec = struct
  type t = state

  let to_int32 x =
    Int32.of_int x

  let of_int32 x =
    Int32.to_int x
end

module Xml_codec = struct
  type t = state

  let to_string =
    string_of_int
end

let to_color_index state =
  state

let clamp_int lo hi x =
  max lo (min hi x)

let normalize_angle dirs angle =
  ((angle mod dirs) + dirs) mod dirs

let random_signed rng amplitude =
  if amplitude <= 0 then
    0
  else
    Rng.range_int rng ~min:(-amplitude) ~max:amplitude

let offset_of_angle dirs angle =
  let tau =
    2.0 *. Float.pi
  in

  let theta =
    tau *. float angle /. float dirs
  in

  let dc =
    int_of_float (Float.round (cos theta))
  in

  let dr =
    int_of_float (Float.round (sin theta))
  in

  let dr, dc =
    if dr = 0 && dc = 0 then
      0, 1
    else
      dr, dc
  in

  dr, dc

let drift_angle rng (params : params) angle =
  normalize_angle params.dirs
    (angle + random_signed rng params.wiggle)

let spontaneous_angle rng (params : params) angle =
  if Rng.int rng (max 1 params.persistence) = 0 then
    Rng.int rng params.dirs
  else
    drift_angle rng params angle

let min_turn_units (params : params) =
  max 1 ((params.dirs * max 0 params.min_turn) / 360)

let collision_angle rng (params : params) angle =
  let min_turn =
    min (params.dirs / 2) (min_turn_units params)
  in

  let span =
    max 1 (params.dirs - 2 * min_turn + 1)
  in

  let delta =
    min_turn + Rng.int rng span
  in

  normalize_angle params.dirs (angle + delta)

let speed rng (params : params) =
  if Rng.chance rng params.fast_prob then
    max 1 params.fast_step
  else
    max 1 params.base_step

let geometry_of_params (params : params) =
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

let initial_agents (params : params) grid =
  let rng =
    Rng.create params.seed
  in

  let coords =
    Initial_geometry.select grid (geometry_of_params params)
    |> Initial_geometry.random_subset rng ~n:params.agents
  in

  Array.mapi
    (fun id coord ->
       {
         id;
         row = coord.Grid.row;
         col = coord.Grid.col;
         age = 1;
         angle = Rng.int rng params.dirs;
       })
    coords

let empty_frame grid =
  Array.init (Grid.rows grid) (fun _ ->
      Array.make (Grid.cols grid) 0)

let frame_of_agents (params : params) grid agents =
  let frame =
    empty_frame grid
  in

  Array.iter
    (fun ag ->
       if ag.row >= 0
          && ag.row < Grid.rows grid
          && ag.col >= 0
          && ag.col < Grid.cols grid
       then
         frame.(ag.row).(ag.col) <-
           1 + clamp_int 0 params.max_age ag.age)
    agents;

  frame

let occupied_table agents =
  let table =
    Hashtbl.create (Array.length agents * 2)
  in

  Array.iter
    (fun ag ->
       Hashtbl.replace table (ag.row, ag.col) ag.id)
    agents;

  table

let normalize_coord grid row col =
  Grid.normalize grid { Grid.row; col }

let target_after_steps grid occupied reserved ag dr dc steps =
  let rec loop row col k =
    if k = 0 then
      normalize_coord grid row col
    else
      match normalize_coord grid (row + dr) (col + dc) with
      | None ->
          None

      | Some coord ->
          let key =
            coord.Grid.row, coord.Grid.col
          in

          let blocked_by_old_agent =
            match Hashtbl.find_opt occupied key with
            | None -> false
            | Some id -> id <> ag.id
          in

          let blocked_by_new_agent =
            Hashtbl.mem reserved key
          in

          if blocked_by_old_agent || blocked_by_new_agent then
            None
          else
            loop coord.Grid.row coord.Grid.col (k - 1)
  in

  loop ag.row ag.col steps

let step_agents rng (params : params) grid agents =
  let occupied =
    occupied_table agents
  in

  let reserved =
    Hashtbl.create (Array.length agents * 2)
  in

  let proposals =
    Array.map
      (fun ag ->
         let angle =
           spontaneous_angle rng params ag.angle
         in

         let dr, dc =
           offset_of_angle params.dirs angle
         in

         let steps =
           speed rng params
         in

         match target_after_steps grid occupied reserved ag dr dc steps with
         | Some target ->
             Hashtbl.replace reserved (target.Grid.row, target.Grid.col) ag.id;

             {
               ag with
               row = target.Grid.row;
               col = target.Grid.col;
               angle;
               age = min params.max_age (ag.age + 1);
             }

         | None ->
             {
               ag with
               angle = collision_angle rng params angle;
               age = min params.max_age (ag.age + 1);
             })
      agents
  in

  proposals


let simulate params grid generations =
  let rng =
    Rng.create params.seed
  in

  let frames =
    Array.make (generations + 1) [||]
  in

  let trace =
    ref []
  in

  let agents =
    ref (initial_agents params grid)
  in

  let record generation =
    Array.iter
      (fun ag ->
         trace := trace_record params generation ag :: !trace)
      !agents
  in

  frames.(0) <- frame_of_agents params grid !agents;
  record 0;

  for generation = 1 to generations do
    agents := step_agents rng params grid !agents;
    frames.(generation) <- frame_of_agents params grid !agents;
    record generation
  done;

  frames, Array.of_list (List.rev !trace)


let metadata (rule_def : rule_def) ~rows ~cols ~generations ~seed ~density ~agents ~topology =
  Abca_io.Metadata.of_list [
    "model", rule_def.id;
    "family", "biological";
    "kind", "agent-based";
    "rows", string_of_int rows;
    "cols", string_of_int cols;
    "generations", string_of_int generations;
    "seed", string_of_int seed;
    "density", string_of_float density;
    "agents", string_of_int agents;
    "topology",
      (match topology with
       | Grid.Bounded -> "bounded"
       | Grid.Toroidal -> "toroidal");
    "init", string_of_init_shape rule_def.init_shape;
    "radius", string_of_float rule_def.radius;
    "thickness", string_of_float rule_def.thickness;
    "dirs", string_of_int rule_def.dirs;
    "base_step", string_of_int rule_def.base_step;
    "fast_step", string_of_int rule_def.fast_step;
    "fast_prob", string_of_float rule_def.fast_prob;
    "wiggle", string_of_int rule_def.wiggle;
    "persistence", string_of_int rule_def.persistence;
    "min_turn", string_of_int rule_def.min_turn;
    "max_age", string_of_int rule_def.max_age;
  ]

let run_for rule_def ~rows ~cols ~generations ~seed ~density ~agents ~topology ~output =
  let agent_count =
    match agents with
    | Some n -> n
    | None -> rule_def.agents
  in

  let params =
    {
      seed;
      dirs = max 8 rule_def.dirs;
      base_step = rule_def.base_step;
      fast_step = rule_def.fast_step;
      fast_prob = rule_def.fast_prob;
      wiggle = rule_def.wiggle;
      persistence = rule_def.persistence;
      min_turn = rule_def.min_turn;
      max_age = rule_def.max_age;
      agents = agent_count;
      init_shape = rule_def.init_shape;
      radius = rule_def.radius;
      thickness = rule_def.thickness;
    }
  in

  let grid = Grid.create ~topology ~rows ~cols () in
  let frames, agents = simulate params grid generations in

  let metadata =
    metadata rule_def
      ~rows
      ~cols
      ~generations
      ~seed
      ~density
      ~agents:agent_count
      ~topology
  in

  let archive =
    Abca_io.Binary.make_archive
      ~rows
      ~cols
      ~generation:generations
      ~metadata
      ~frames
      ~agents
      ()
  in

  Abca_io.Binary.save
    ~filename:output
    ~archive
    ~codec:(module Binary_codec)



let export_xml_for (rule_def : rule_def) ~input ~output =
  let open Abca_io.Binary in
  let { header; frames; _ } =
    load
      ~filename:input
      ~codec:(module Binary_codec)
  in

  let grid =
    Grid.create
      ~rows:header.rows
      ~cols:header.cols
      ()
  in

  Abca_io.Xml.save_frames
    ~filename:output
    ~model:rule_def.id
    ~grid
    ~generation:header.generation
    ~frames
    ~codec:(module Xml_codec)

let description rule_def =
  Printf.sprintf
    "%s zoospore swimming model: agents=%d, init=%s, radius=%.1f, thickness=%.1f"
    rule_def.label
    rule_def.agents
    (string_of_init_shape rule_def.init_shape)
    rule_def.radius
    rule_def.thickness

let make_model (rule_def : rule_def) =
  {
    Abca_models.Model.name = rule_def.id;
    family = Abca_models.Model.Biological;
    kind = Abca_models.Model.Agent_based_model;
    description = description rule_def;

    state_count = rule_def.max_age + 2;
    to_color_index;

    run = run_for rule_def;
    export_xml = export_xml_for rule_def;
  }

let models =
  load_rules rules_file
  |> List.map make_model
