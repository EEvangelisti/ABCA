type color = float * float * float

type palette = {
  background : color;
  colors     : color array;
}

let default_palette =
  {
    background = (1.0, 1.0, 1.0);
    colors = [|
      (1.0, 1.0, 1.0);  (* 0: empty/dead *)
      (0.0, 0.0, 0.0);  (* 1: alive/occupied *)
    |];
  }

let set_source_rgb cr (r, g, b) =
  Cairo.set_source_rgb cr r g b

let check_frame frame =
  if Array.length frame = 0 then
    invalid_arg "Png: empty frame";

  let cols = Array.length frame.(0) in

  if cols = 0 then
    invalid_arg "Png: empty rows";

  Array.iter
    (fun row ->
       if Array.length row <> cols then
         invalid_arg "Png: irregular frame")
    frame;

  Array.length frame, cols

let clear cr ~w ~h color =
  set_source_rgb cr color;
  Cairo.rectangle cr 0.0 0.0 ~w:(float w) ~h:(float h);
  Cairo.fill cr

let draw_cell cr ~cell_size ~row ~col color =
  let x = float (col * cell_size) in
  let y = float (row * cell_size) in
  let s = float cell_size in

  set_source_rgb cr color;
  Cairo.rectangle cr x y ~w:s ~h:s;
  Cairo.fill cr

let save_frame
    ~filename
    ~cell_size
    ?background
    ?skip_index
    ~palette
    ~to_color_index
    frame =

  if cell_size <= 0 then
    invalid_arg "Png.save_frame: cell_size must be positive";

  let rows, cols = check_frame frame in
  let width = cols * cell_size in
  let height = rows * cell_size in

  let surface =
    Cairo.Image.create Cairo.Image.RGB24 ~w:width ~h:height
  in
  let cr = Cairo.create surface in

  let background =
    match background with
    | Some color -> color
    | None -> palette.background
  in

  clear cr ~w:width ~h:height background;

  Cairo.set_antialias cr Cairo.ANTIALIAS_NONE;
  clear cr ~w:width ~h:height background;

  Array.iteri
    (fun row cells ->
       Array.iteri
         (fun col state ->
            let index = to_color_index state in

            match skip_index with
            | Some skip when index = skip ->
                ()

            | _ ->
                if index < 0 || index >= Array.length palette.colors then
                  invalid_arg "Png.save_frame: invalid color index";

                let color = palette.colors.(index) in
                draw_cell cr ~cell_size ~row ~col color)
         cells)
    frame;

  Cairo.PNG.write surface filename

let ensure_dir dirname =
  if Sys.file_exists dirname then begin
    if not (Sys.is_directory dirname) then
      invalid_arg ("Png.ensure_dir: not a directory: " ^ dirname)
  end else
    Unix.mkdir dirname 0o755

let frame_filename ~dirname ~prefix index =
  Filename.concat dirname
    (Printf.sprintf "%s_%06d.png" prefix index)

let save_frames
    ~dirname
    ~prefix
    ~every
    ~cell_size
    ?background
    ?skip_index
    ~palette
    ~to_color_index
    frames =

  if every <= 0 then
    invalid_arg "Png.save_frames: every must be positive";

  ensure_dir dirname;

  let output_index = ref 0 in

  Array.iteri
    (fun i frame ->
       if i mod every = 0 then begin
         save_frame
           ~filename:(frame_filename ~dirname ~prefix !output_index)
           ~cell_size
           ?background
           ?skip_index
           ~palette
           ~to_color_index
           frame;

         incr output_index
       end)
    frames
