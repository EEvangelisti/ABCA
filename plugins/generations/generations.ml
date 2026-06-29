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

type params = {
  density  : float;
  seed     : int;
  states   : int;
  survival : int list;
  birth    : int list;
}

type rule_def = {
  id       : string;
  label    : string;
  survival : int list;
  birth    : int list;
  states   : int;
  raw_rule : string;
}

let rules_file =
  Filename.concat "plugins/generations" "generations.rules"

let trim =
  String.trim

let slugify s =
  s
  |> String.lowercase_ascii
  |> String.map (function
      | ' ' | '_' -> '-'
      | c -> c)

let parse_digits s =
  s
  |> String.to_seq
  |> Seq.filter (fun c -> c >= '0' && c <= '8')
  |> Seq.map (fun c -> Char.code c - Char.code '0')
  |> List.of_seq

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

let parse_rule_line line =
  let line =
    trim line
  in

  if line = "" || line.[0] = '#' then
    None
  else
    try
      Scanf.sscanf line
        "AUTOMATON %S: %[^/]/%[^/]/%d"
        (fun label survival birth states ->
           Some {
             id = "gen-" ^ slugify label;
             label;
             survival = parse_digits survival;
             birth = parse_digits birth;
             states = max 2 states;
             raw_rule =
               Printf.sprintf "%s/%s/%d" survival birth states;
           })
    with _ ->
      failwith ("Generations: cannot parse rule line: " ^ line)

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

let has n xs =
  List.exists (( = ) n) xs

let initial params grid =
  let rng =
    Rng.create params.seed
  in

  Grid.map_coords grid (fun _ ->
      if Rng.chance rng params.density then 1 else 0)

let active_neighbors grid frame coord =
  Grid.moore_neighbors grid coord
  |> List.fold_left
    (fun acc { Grid.row; col } ->
       if frame.(row).(col) = 1 then acc + 1 else acc)
    0

let next (params : params) grid frame coord =
  let current =
    frame.(coord.Grid.row).(coord.Grid.col)
  in

  let neighbours =
    active_neighbors grid frame coord
  in

  match current with
  | 0 ->
      if has neighbours params.birth then
        1
      else
        0

  | 1 ->
      if has neighbours params.survival then
        1
      else
        2

  | n ->
      if n < params.states - 1 then
        n + 1
      else
        0

let make_rule rule_def =
  Rule.of_module
    (module struct
      type nonrec state = state
      type nonrec params = params

      let name =
        rule_def.id

      let initial =
        initial

      let next =
        next
    end)

let run_for rule_def ~rows ~cols ~generations ~seed ~density ~agents:_ ~topology ~output =
  let grid =
    Grid.create ~topology ~rows ~cols ()
  in

  let params =
    {
      density;
      seed;
      states = rule_def.states;
      survival = rule_def.survival;
      birth = rule_def.birth;
    }
  in

  let sim =
    Simulation.create
      ~model:rule_def.id
      ~grid
      ~rule:(make_rule rule_def)
      ~params
      ()
    |> Simulation.run generations
  in

  let frames =
    match Simulation.history sim with
    | Some frames -> frames
    | None -> failwith "History disabled"
  in

  let metadata =
    Abca_io.Metadata.of_list [
      "model", rule_def.id;
      "family", "generations";
      "seed", string_of_int seed;
      "density", string_of_float density;
      "rows", string_of_int rows;
      "cols", string_of_int cols;
      "generations", string_of_int generations;
    ]
  in

  let binary_simulation =
    Abca_io.Binary.make_simulation
      ~rows
      ~cols
      ~generation:(Simulation.generation sim)
      ~metadata
      ~frames
      ()
  in

  Abca_io.Binary.save
    ~filename:output
    ~simulation:binary_simulation
    ~codec:(module Binary_codec)



let export_xml_for rule_def ~input ~output =
  let header, frames, _agents =
    Abca_io.Binary.load_frames
      ~filename:input
      ~codec:(module Binary_codec)
  in

  let grid =
    Grid.create
      ~rows:header.Abca_io.Binary.rows
      ~cols:header.Abca_io.Binary.cols
      ()
  in

  Abca_io.Xml.save_frames
    ~filename:output
    ~model:rule_def.id
    ~grid
    ~generation:header.Abca_io.Binary.generation
    ~frames
    ~codec:(module Xml_codec)

let description rule_def =
  Printf.sprintf
    "%s Generations automaton (%s)"
    rule_def.label
    rule_def.raw_rule

let make_model rule_def =
  {
    Abca_models.Model.name = rule_def.id;
    family = Abca_models.Model.Generations;
    kind = Abca_models.Model.Cellular_automaton;
    description = description rule_def;

    run = run_for rule_def;
    export_xml = export_xml_for rule_def;
    state_count = rule_def.states;
    to_color_index
  }

let models =
  load_rules rules_file
  |> List.map make_model
