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

let shell_quote s =
  "'" ^ String.concat "'\\''" (String.split_on_char '\'' s) ^ "'"

let run_command ?log_file cmd =
  let cmd =
    match log_file with
    | None ->
        cmd ^ " > /dev/null 2>&1"
    | Some log ->
        cmd ^ " >> " ^ shell_quote log ^ " 2>&1"
  in

  match Sys.command cmd with
  | 0 -> ()
  | n ->
      Printf.eprintf "Command failed with exit code %d\n%!" n;
      Printf.eprintf "Command was: %s\n%!" cmd;
      exit n

let png_pattern ~png_dir ~prefix =
  Filename.concat png_dir (prefix ^ "_%06d.png")

let make_gif ?log_file ~fps ~png_dir ~prefix ~output () =
  if fps <= 0 then
    invalid_arg "Video.make_gif: fps must be positive";

  let palette =
    Filename.concat png_dir "palette.png"
  in

  run_command ?log_file
    (Printf.sprintf
       "ffmpeg -y -framerate %d -i %s -vf palettegen %s"
       fps
       (shell_quote (png_pattern ~png_dir ~prefix))
       (shell_quote palette));

  run_command ?log_file
    (Printf.sprintf
       "ffmpeg -y -framerate %d -i %s -i %s -lavfi paletteuse -loop 0 %s"
       fps
       (shell_quote (png_pattern ~png_dir ~prefix))
       (shell_quote palette)
       (shell_quote output))

let make_mp4 ?log_file ~fps ~png_dir ~prefix ~output () =
  if fps <= 0 then
    invalid_arg "Video.make_mp4: fps must be positive";

  run_command ?log_file
    (Printf.sprintf
       "ffmpeg -y -framerate %d -i %s -c:v libx264 -pix_fmt yuv420p %s"
       fps
       (shell_quote (png_pattern ~png_dir ~prefix))
       (shell_quote output))
