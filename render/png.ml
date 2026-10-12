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

type color = float * float * float
type palette = { background : color; colors : color array }
let default_palette = {
  background = (1., 1., 1.);
  colors = [| (1., 1., 1.); (0., 0., 0.) |];
}
let check_color (r,g,b) =
  List.iter (fun x -> if not (Float.is_finite x) || x < 0. || x > 1. then
    invalid_arg "Png: RGB components must be finite and in [0,1]") [r;g;b]
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
let ensure_dir dirname =
  if Sys.file_exists dirname then begin
    if not (Sys.is_directory dirname) then
      invalid_arg ("Png.ensure_dir: not a directory: " ^ dirname)
  end else Unix.mkdir dirname 0o755
let frame_filename ~dirname ~prefix index =
  Filename.concat dirname (Printf.sprintf "%s_%06d.png" prefix index)
let save_frame ~filename ~cell_size ?background ~palette ~to_color_index frame =
  let rows, cols = check_frame frame in
  let width, height = dimensions ~rows ~cols ~cell_size in
  let bg = match background with Some c -> c | None -> palette.background in
  check_color bg;
  let surface = Cairo.Image.create Cairo.Image.RGB24 ~w:width ~h:height in
  let cr = Cairo.create surface in
  Cairo.set_antialias cr Cairo.ANTIALIAS_NONE;
  let set_color (r,g,b) = Cairo.set_source_rgb cr r g b in
  set_color bg;
  Cairo.rectangle cr 0. 0. ~w:(float width) ~h:(float height);
  Cairo.fill cr;
  Array.iteri (fun row cells ->
    Array.iteri (fun col state ->
      match to_color_index state with
      | None -> ()
      | Some idx ->
          if idx < 0 || idx >= Array.length palette.colors then
            invalid_arg "Png.save_frame: invalid color index";
          let color = palette.colors.(idx) in
          check_color color;
          set_color color;
          Cairo.rectangle cr (float (col * cell_size)) (float (row * cell_size))
            ~w:(float cell_size) ~h:(float cell_size);
          Cairo.fill cr
    ) cells
  ) frame;
  Cairo.PNG.write surface filename
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
