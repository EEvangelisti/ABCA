open Abca

type state = int

type init_shape =
  | Init_full
  | Init_disk
  | Init_ring

type params = {
  initial_speeds : float array;
  initial_speeds_file : string;
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
  previous_turn_rad : float;
  first_step : bool;
}

let parse_init_shape s =
  match String.uppercase_ascii (String.trim s) with
  | "FULL" | "RANDOM" -> Init_full
  | "DISK" | "CIRCLE" -> Init_disk
  | "RING" -> Init_ring
  | other -> failwith ("Zoospore discovered: unknown INIT shape: " ^ other)

let string_of_init_shape = function
  | Init_full -> "full"
  | Init_disk -> "disk"
  | Init_ring -> "ring"

let geometry_of_params params =
  match params.init_shape with
  | Init_full -> Initial_geometry.Full_grid
  | Init_disk ->
      Initial_geometry.Disk { center = None; radius = params.radius }
  | Init_ring ->
      Initial_geometry.Ring {
        center = None;
        radius = params.radius;
        thickness = params.thickness;
      }

let normalize_degrees angle =
  let a = mod_float angle 360.0 in
  if a < 0.0 then a +. 360.0 else a

let wrap_radians angle =
  let a = mod_float (angle +. Float.pi) (2.0 *. Float.pi) in
  (if a < 0.0 then a +. 2.0 *. Float.pi else a) -. Float.pi

let clamp lo hi x = max lo (min hi x)

let row_of_agent ag = int_of_float (Float.floor ag.y)
let col_of_agent ag = int_of_float (Float.floor ag.x)
let coord_of_agent ag =
  { Grid.row = row_of_agent ag; col = col_of_agent ag }

let state_of_agent _ = 1

let standard_normal rng =
  let u1 = max 0x1p-53 (Rng.float rng 1.0) in
  let u2 = Rng.float rng 1.0 in
  sqrt (-2.0 *. log u1) *. cos (2.0 *. Float.pi *. u2)

(* Frozen coefficients from discovered-swimming-v1.1. *)
let eps = 0.001

let mu =
  [|
    5.109096593781684;
    26.613826008061093;
    -0.0016994856337493266;
    0.8233777909891786;
  |]

let sd =
  [|
    0.7148132647534579;
    5.868154706396466;
    0.3143780479745454;
    0.44189915705909844;
  |]

let beta =
  [|
    [|
      5.110485927873919;
      0.4802221621989367;
      0.05182049567615058;
      0.007939219627389988;
      0.04833914563914514;
    |];
    [|
      0.8467642239558473;
      0.09089249295575834;
      0.03977481940435128;
      0.004702149391659664;
      0.12164881294418195;
    |];
    [|
      -0.0016397907666950828;
      -0.0001865864456041774;
      -0.0032291897266399057;
      -0.03164100161990235;
      0.005494544931865358;
    |];
  |]

let sigma =
  [|
    0.4528938152785168;
    0.3692732369204068;
    0.31713931312626353;
  |]

let discovered_step rng ~first_step ~speed ~previous_turn_rad =
  let log_speed = log (speed +. eps) in
  let raw =
    [|
      log_speed;
      log_speed *. log_speed;
      (if first_step then 0.0 else sin previous_turn_rad);
      (if first_step then 0.0 else cos previous_turn_rad);
    |]
  in
  let features = Array.make 5 1.0 in
  for i = 0 to 3 do
    features.(i + 1) <- (raw.(i) -. mu.(i)) /. sd.(i)
  done;
  let dot coefficients =
    let s = ref 0.0 in
    for i = 0 to 4 do
      s := !s +. coefficients.(i) *. features.(i)
    done;
    !s
  in
  let z =
    Array.init 3 (fun j ->
        dot beta.(j) +. sigma.(j) *. standard_normal rng)
  in
  let next_speed = max 0.0 (exp z.(0) -. eps) in
  let turn =
    if z.(1) = 0.0 && z.(2) = 0.0 then 0.0
    else wrap_radians (atan2 z.(2) z.(1))
  in
  next_speed, turn

let wrap_coordinate size x =
  let s = float_of_int size in
  let y = mod_float x s in
  if y < 0.0 then y +. s else y

let reflected_heading rows cols x y heading =
  let h = ref heading in
  if x < 0.0 || x >= float_of_int cols then h := 180.0 -. !h;
  if y < 0.0 || y >= float_of_int rows then h := -. !h;
  normalize_degrees !h

let move_agent params grid ag heading_deg speed_um_s =
  let distance_cells =
    speed_um_s *. params.dt /. params.microns_per_cell
  in
  let theta = heading_deg *. Float.pi /. 180.0 in
  let x1 = ag.x +. distance_cells *. cos theta in
  let y1 = ag.y +. distance_cells *. sin theta in
  match params.topology with
  | Grid.Toroidal ->
      wrap_coordinate (Grid.cols grid) x1,
      wrap_coordinate (Grid.rows grid) y1,
      heading_deg
  | Grid.Bounded ->
      if x1 >= 0.0 && x1 < float_of_int (Grid.cols grid)
         && y1 >= 0.0 && y1 < float_of_int (Grid.rows grid)
      then x1, y1, heading_deg
      else
        let reflected =
          reflected_heading
            (Grid.rows grid) (Grid.cols grid) x1 y1 heading_deg
        in
        let theta2 = reflected *. Float.pi /. 180.0 in
        let x2 = ag.x +. distance_cells *. cos theta2 in
        let y2 = ag.y +. distance_cells *. sin theta2 in
        clamp 0.0 (float_of_int (Grid.cols grid) -. 1e-9) x2,
        clamp 0.0 (float_of_int (Grid.rows grid) -. 1e-9) y2,
        reflected

let initial_agents rng params grid =
  if Array.length params.initial_speeds = 0 then
    invalid_arg "Zoospore discovered: initial speed distribution is empty";
  let coords =
    Initial_geometry.select grid (geometry_of_params params)
    |> Initial_geometry.random_subset rng ~n:params.agents
  in
  Array.mapi
    (fun id coord ->
       let speed =
         params.initial_speeds.(Rng.int rng (Array.length params.initial_speeds))
       in
       {
         id;
         x = float_of_int coord.Grid.col +. 0.5;
         y = float_of_int coord.Grid.row +. 0.5;
         age = 1;
         heading_deg = Rng.float rng 360.0;
         speed_um_s = speed;
         previous_turn_rad = 0.0;
         first_step = true;
       })
    coords

let step_agent rng params grid ag =
  let speed_um_s, turn_rad =
    discovered_step rng
      ~first_step:ag.first_step
      ~speed:ag.speed_um_s
      ~previous_turn_rad:ag.previous_turn_rad
  in
  let heading_deg =
    normalize_degrees
      (ag.heading_deg +. turn_rad *. 180.0 /. Float.pi)
  in
  let x, y, heading_deg =
    move_agent params grid ag heading_deg speed_um_s
  in
  {
    ag with
    x;
    y;
    age = min params.max_age (ag.age + 1);
    heading_deg;
    speed_um_s;
    previous_turn_rad = turn_rad;
    first_step = false;
  }

let empty_frame grid =
  Array.init (Grid.rows grid) (fun _ -> Array.make (Grid.cols grid) 0)

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
      int_of_float (Float.round (normalize_degrees ag.heading_deg)) mod 360;
    age = ag.age;
    state = state_of_agent ag;
  }

let simulate params grid generations =
  let rng = Rng.create params.seed in
  let frames = Array.make (generations + 1) [||] in
  let trace = ref [] in
  let agents = ref (initial_agents rng params grid) in
  let record generation =
    Array.iter
      (fun ag -> trace := trace_record generation ag :: !trace)
      !agents
  in
  frames.(0) <- frame_of_agents grid !agents;
  record 0;
  for generation = 1 to generations do
    agents := Array.map (step_agent rng params grid) !agents;
    frames.(generation) <- frame_of_agents grid !agents;
    record generation
  done;
  frames, Array.of_list (List.rev !trace)
