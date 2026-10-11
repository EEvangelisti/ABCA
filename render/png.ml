(* ABCA - PNG rendering utilities. MIT License, (c) 2026 Edouard Evangelisti. *)
type color = float * float * float
type palette = { background : color; colors : color array }

type point_style = {
  radius : float;
  alpha : float;
  antialias : bool;
  multiplicity : bool;
}

let default_palette = {
  background = (1., 1., 1.);
  colors = [| (1., 1., 1.); (0., 0., 0.) |];
}

let default_point_style = {
  radius = 1.6;
  alpha = 0.60;
  antialias = true;
  multiplicity = true;
}

let check_color (r,g,b) =
  List.iter (fun x -> if not (Float.is_finite x) || x < 0. || x > 1. then
    invalid_arg "Png: RGB components must be finite and in [0,1]") [r;g;b]

let set_source_rgb cr (r,g,b) = Cairo.set_source_rgb cr r g b
let set_source_rgba cr (r,g,b) a = Cairo.set_source_rgba cr r g b a

let check_frame frame =
  if Array.length frame = 0 then invalid_arg "Png: empty frame";
  let cols = Array.length frame.(0) in
  if cols = 0 then invalid_arg "Png: empty rows";
  Array.iter (fun row -> if Array.length row <> cols then
    invalid_arg "Png: irregular frame") frame;
  (Array.length frame, cols)

let dimensions ~rows ~cols ~cell_size =
  if cell_size <= 0 then invalid_arg "Png: cell_size must be positive";
  if rows > max_int / cell_size || cols > max_int / cell_size then
    invalid_arg "Png: image dimensions overflow";
  (cols * cell_size, rows * cell_size)

let clear cr ~w ~h color =
  check_color color;
  set_source_rgb cr color;
  Cairo.rectangle cr 0. 0. ~w:(float w) ~h:(float h);
  Cairo.fill cr

let create_canvas ~width ~height ~background ~antialias =
  let surface = Cairo.Image.create Cairo.Image.RGB24 ~w:width ~h:height in
  let cr = Cairo.create surface in
  Cairo.set_antialias cr (if antialias then Cairo.ANTIALIAS_DEFAULT else Cairo.ANTIALIAS_NONE);
  clear cr ~w:width ~h:height background;
  (surface, cr)

let ensure_dir dirname =
  if Sys.file_exists dirname then begin
    if not (Sys.is_directory dirname) then
      invalid_arg ("Png.ensure_dir: not a directory: " ^ dirname)
  end else Unix.mkdir dirname 0o755

let frame_filename ~dirname ~prefix index =
  Filename.concat dirname (Printf.sprintf "%s_%06d.png" prefix index)

let save_square_frame ~filename ~cell_size ?background ~palette ~to_color_index frame =
  let rows, cols = check_frame frame in
  let width, height = dimensions ~rows ~cols ~cell_size in
  let bg = match background with Some c -> c | None -> palette.background in
  let surface, cr = create_canvas ~width ~height ~background:bg ~antialias:false in
  Array.iteri (fun row cells ->
    Array.iteri (fun col state ->
      match to_color_index state with
      | None -> ()
      | Some idx ->
          if idx < 0 || idx >= Array.length palette.colors then
            invalid_arg "Png.save_frame: invalid color index";
          let color = palette.colors.(idx) in
          check_color color;
          set_source_rgb cr color;
          Cairo.rectangle cr (float (col * cell_size)) (float (row * cell_size))
            ~w:(float cell_size) ~h:(float cell_size);
          Cairo.fill cr
    ) cells
  ) frame;
  Cairo.PNG.write surface filename

let check_style style =
  if not (Float.is_finite style.radius) || style.radius <= 0. then
    invalid_arg "Png: point radius must be finite and positive";
  if not (Float.is_finite style.alpha) || style.alpha < 0. || style.alpha > 1. then
    invalid_arg "Png: alpha must be in [0,1]"

let draw_dot cr ~x ~y ~radius ~color ~alpha =
  if alpha > 0. then begin
    set_source_rgba cr color alpha;
    Cairo.arc cr x y ~r:radius ~a1:0. ~a2:(2. *. Float.pi);
    Cairo.fill cr
  end

(* Alpha compositing n identical dots is 1-(1-alpha)^n. *)
let combined_alpha alpha count =
  if count <= 0 then 0.
  else if alpha >= 1. then 1.
  else 1. -. (1. -. alpha) ** float count

let save_point_frame
    ~filename ~cell_size ?background ~palette ~to_color_index
    ?(style=default_point_style) frame =
  let rows, cols = check_frame frame in
  let width, height = dimensions ~rows ~cols ~cell_size in
  check_style style;
  let bg = match background with Some c -> c | None -> palette.background in
  let surface, cr = create_canvas ~width ~height ~background:bg ~antialias:style.antialias in
  Array.iteri (fun row cells -> Array.iteri (fun col state ->
    match to_color_index state with
    | None -> ()
    | Some idx ->
        if idx < 0 || idx >= Array.length palette.colors then
          invalid_arg "Png.save_point_frame: invalid color index";
        let color = palette.colors.(idx) in
        check_color color;
        draw_dot cr ~x:((float col +. 0.5) *. float cell_size)
          ~y:((float row +. 0.5) *. float cell_size)
          ~radius:style.radius ~color ~alpha:style.alpha
  ) cells) frame;
  Cairo.PNG.write surface filename

let save_point_frames
    ~dirname ~prefix ~every ~cell_size ?background ~palette ~to_color_index
    ?(style=default_point_style) frames =
  if every <= 0 then invalid_arg "Png.save_point_frames: every must be positive";
  ensure_dir dirname;
  let output_index = ref 0 in
  Array.iteri (fun i frame -> if i mod every = 0 then begin
    save_point_frame ~filename:(frame_filename ~dirname ~prefix !output_index)
      ~cell_size ?background ~palette ~to_color_index ~style frame;
    incr output_index
  end) frames


(* Existing calls now write two images: the original square-grid PNG at
   [filename] and an antialiased point rendering at [*_points.png]. *)
let point_filename filename =
  let stem =
    if Filename.check_suffix filename ".png" then
      Filename.chop_suffix filename ".png"
    else filename
  in
  stem ^ "_points.png"

let save_frame ~filename ~cell_size ?background ~palette ~to_color_index frame =
  save_square_frame ~filename ~cell_size ?background ~palette ~to_color_index frame;
  save_point_frame ~filename:(point_filename filename) ~cell_size
    ?background ~palette ~to_color_index frame

let save_frames ~dirname ~prefix ~every ~cell_size ?background ~palette ~to_color_index frames =
  if every <= 0 then invalid_arg "Png.save_frames: every must be positive";
  ensure_dir dirname;
  let output_index = ref 0 in
  Array.iteri (fun i frame ->
    if i mod every = 0 then begin
      save_frame ~filename:(frame_filename ~dirname ~prefix !output_index)
        ~cell_size ?background ~palette ~to_color_index frame;
      incr output_index
    end) frames

(* Count-aware rendering: an integer grid stores the number of agents per cell. *)
let save_count_frame ~filename ~cell_size ?(background=(1.,1.,1.))
    ?(color=(0.121,0.466,0.705)) ?(style=default_point_style) counts =
  let rows, cols = check_frame counts in
  let width, height = dimensions ~rows ~cols ~cell_size in
  check_style style; check_color color;
  let surface, cr = create_canvas ~width ~height ~background ~antialias:style.antialias in
  Array.iteri (fun row cells -> Array.iteri (fun col n ->
    if n < 0 then invalid_arg "Png.save_count_frame: negative agent count";
    if n > 0 then
      let alpha = if style.multiplicity then combined_alpha style.alpha n else style.alpha in
      draw_dot cr ~x:((float col +. 0.5) *. float cell_size)
        ~y:((float row +. 0.5) *. float cell_size)
        ~radius:style.radius ~color ~alpha
  ) cells) counts;
  Cairo.PNG.write surface filename

(* Floating-point coordinates are in cell units, not pixels. Coordinates
   (0,0) and (cols,rows) correspond to the canvas edges. No grid quantization. *)
let save_xy_points ~filename ~rows ~cols ~cell_size
    ?(background=(1.,1.,1.)) ?(color=(0.121,0.466,0.705))
    ?(style=default_point_style) points =
  if rows <= 0 || cols <= 0 then invalid_arg "Png.save_xy_points: invalid grid size";
  let width, height = dimensions ~rows ~cols ~cell_size in
  check_style style; check_color color;
  let surface, cr = create_canvas ~width ~height ~background ~antialias:style.antialias in
  Array.iter (fun (x,y) ->
    if not (Float.is_finite x && Float.is_finite y) then
      invalid_arg "Png.save_xy_points: non-finite coordinate";
    if x >= 0. && x <= float cols && y >= 0. && y <= float rows then
      draw_dot cr ~x:(x *. float cell_size) ~y:(y *. float cell_size)
        ~radius:style.radius ~color ~alpha:style.alpha
  ) points;
  Cairo.PNG.write surface filename
