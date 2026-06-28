(* engine.ml *)

type ('state, 'params) t = {
  grid         : Grid.t;
  rule         : ('state, 'params) Rule.t;
  params       : 'params;
  generation   : int;
  current      : 'state array array;
  history      : 'state array array list option;
}

let create ~grid ~rule ~params ?(keep_history = true) () =
  let initial = rule.Rule.initial params grid in
  {
    grid;
    rule;
    params;
    generation = 0;
    current = initial;
    history =
      if keep_history then Some [initial]
      else None;
  }

let grid e =
  e.grid

let rule_name e =
  e.rule.Rule.name

let params e =
  e.params

let generation e =
  e.generation

let current e =
  e.current

let history e =
  match e.history with
  | None -> None
  | Some frames ->
      Some (Array.of_list (List.rev frames))

let check_shape e frame =
  let rows = Grid.rows e.grid in
  let cols = Grid.cols e.grid in
  if Array.length frame <> rows then
    invalid_arg "Engine: frame has invalid row count";
  Array.iter
    (fun row ->
       if Array.length row <> cols then
         invalid_arg "Engine: frame has invalid column count")
    frame

let compute_next e =
  let rows = Grid.rows e.grid in
  let cols = Grid.cols e.grid in

  Array.init rows (fun row ->
      Array.init cols (fun col ->
          let coord = { Grid.row; col } in
          e.rule.Rule.next e.params e.grid e.current coord
        )
    )

let step e =
  check_shape e e.current;
  let next = compute_next e in
  {
    e with
    generation = e.generation + 1;
    current = next;
    history =
      match e.history with
      | None -> None
      | Some frames -> Some (next :: frames);
  }

let run n e =
  if n < 0 then invalid_arg "Engine.run: n must be non-negative";

  let rec loop i acc =
    if i = 0 then acc
    else loop (i - 1) (step acc)
  in

  loop n e
