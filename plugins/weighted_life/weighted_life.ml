open Abca

type state = int

type params = {
  density  : float;
  seed     : int;
  states   : int;
  history  : bool;
  weights  : int array;
  survival : int list;
  birth    : int list;
}

type rule_def = {
  id       : string;
  label    : string;
  states   : int;
  history  : bool;
  weights  : int array;
  survival : int list;
  birth    : int list;
}

let rules_file =
  Filename.concat "plugins/weighted_life" "weighted_life.rules"

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

let parse_weighted_rules s =
  let tokens =
    s
    |> String.split_on_char ' '
    |> List.filter (fun x -> x <> "")
  in

  List.fold_left
    (fun (survival, birth) token ->
       if String.length token < 3 then
         failwith ("Weighted_life: invalid rule token: " ^ token);

       let prefix =
         String.sub token 0 2
       in

       let value =
         int_of_string
           (String.sub token 2 (String.length token - 2))
       in

       match prefix with
       | "RS" -> value :: survival, birth
       | "RB" -> survival, value :: birth
       | _ ->
           failwith ("Weighted_life: invalid rule token: " ^ token))
    ([], [])
    tokens

let parse_rule_line line =
  let line = trim line in

  if line = "" || line.[0] = '#' then
    None
  else
    try
      Scanf.sscanf line
        "AUTOMATON %S: NW%d NN%d NE%d WW%d ME%d EE%d SW%d SS%d SE%d HI%d %[^\n]"
        (fun label nw nn ne ww me ee sw ss se hi rem ->
           let survival, birth =
             parse_weighted_rules rem
           in

           let states =
             if hi = 0 then 255 else max 1 (hi - 1)
           in

           Some {
             id = "wlf-" ^ slugify label;
             label;
             states;
             history = hi > 0;
             weights = [| nw; nn; ne; ww; me; ee; sw; ss; se |];
             survival = List.rev survival;
             birth = List.rev birth;
           })
    with _ ->
      failwith ("Weighted_life: cannot parse rule line: " ^ line)

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
  if state = 0 then 0 else 1

let weighted_offsets =
  [|
    (-1, -1); (-1,  0); (-1,  1);
    ( 0, -1); ( 0,  0); ( 0,  1);
    ( 1, -1); ( 1,  0); ( 1,  1);
  |]

let active_value (params : params) state =
  if params.history then
    if state = 1 then 1 else 0
  else
    if state <> 0 then 1 else 0

let cell_at grid frame row col =
  match Grid.normalize grid { Grid.row; col } with
  | None -> 0
  | Some { Grid.row; col } -> frame.(row).(col)

let weighted_score (params : params) grid frame coord =
  let score =
    ref 0
  in

  Array.iteri
    (fun k weight ->
       let dr, dc =
         weighted_offsets.(k)
       in

       let row =
         coord.Grid.row + dr
       in

       let col =
         coord.Grid.col + dc
       in

       let state =
         cell_at grid frame row col
       in

       score := !score + (weight * active_value params state))
    params.weights;

  !score

let has n xs =
  List.exists (( = ) n) xs

let initial params grid =
  let rng =
    Rng.create params.seed
  in

  Grid.map_coords grid (fun _ ->
      if Rng.chance rng params.density then 1 else 0)

let next_history (params : params) grid frame coord =
  let current =
    frame.(coord.Grid.row).(coord.Grid.col)
  in

  let score =
    weighted_score params grid frame coord
  in

  match current with
  | 0 ->
      if has score params.birth then 1 else 0

  | 1 ->
      if has score params.survival then 1 else 2

  | n ->
      if n < params.states then n + 1 else 0

let next_no_history (params : params) grid frame coord =
  let current =
    frame.(coord.Grid.row).(coord.Grid.col)
  in

  let score =
    weighted_score params grid frame coord
  in

  match current with
  | 0 ->
      if has score params.birth then 1 else 0

  | n ->
      if has score params.survival then
        min params.states (n + 1)
      else
        0

let next (params : params) grid frame coord =
  if params.history then
    next_history params grid frame coord
  else
    next_no_history params grid frame coord

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
      history = rule_def.history;
      weights = rule_def.weights;
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

  Abca_io.Binary.save_frames
    ~filename:output
    ~grid:(Simulation.grid sim)
    ~generation:(Simulation.generation sim)
    ~metadata:(Abca_io.Metadata.of_list [
      "model", rule_def.id;
      "family", "life-like";
      "seed", string_of_int seed;
      "density", string_of_float density;
      "rows", string_of_int rows;
      "cols", string_of_int cols;
      "generations", string_of_int generations;
    ])
    ~frames
    ~codec:(module Binary_codec)

let export_xml_for rule_def ~input ~output =
  let header, frames =
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

let weights_to_string weights =
  Printf.sprintf
    "NW%d NN%d NE%d WW%d ME%d EE%d SW%d SS%d SE%d"
    weights.(0) weights.(1) weights.(2)
    weights.(3) weights.(4) weights.(5)
    weights.(6) weights.(7) weights.(8)

let rules_to_string prefix xs =
  xs
  |> List.map (fun n -> prefix ^ string_of_int n)
  |> String.concat " "

let description rule_def =
  Printf.sprintf
    "%s weighted Life automaton: %s, %s, %s%s"
    rule_def.label
    (weights_to_string rule_def.weights)
    (rules_to_string "RS" rule_def.survival)
    (rules_to_string "RB" rule_def.birth)
    (if rule_def.history then ", history=true" else "")

let make_model rule_def =
  {
    Abca_models.Model.name = rule_def.id;
    family = Abca_models.Model.Weighted_life;
    kind = Abca_models.Model.Cellular_automaton;
    description = description rule_def;

    run = run_for rule_def;
    export_xml = export_xml_for rule_def;
    state_count = rule_def.states + 1;
    to_color_index
  }

let models =
  load_rules rules_file
  |> List.map make_model
