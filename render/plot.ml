(* ABCA - Delegate scientific spatial plotting to Matplotlib. *)
let render_xml ?(python="python3") ?(script="render_abca_frames.py")
    ?outdir ?width ?height ?rows ?cols ?microns_per_cell
    ?(format="png") ?(dpi=180) ?(size=6.) ?(alpha=0.6)
    ?first ?last ?(step=1) ~xml () =
  if step < 1 then invalid_arg "Plot.render_xml: step must be positive";
  if not (List.mem format ["png"; "svg"; "pdf"]) then
    invalid_arg "Plot.render_xml: unsupported format";
  let args = ref [python; script; xml] in
  let add flag value = args := !args @ [flag; value] in
  let opt flag conv = function None -> () | Some x -> add flag (conv x) in
  opt "--outdir" Fun.id outdir;
  opt "--width" string_of_float width;
  opt "--height" string_of_float height;
  opt "--rows" string_of_int rows;
  opt "--cols" string_of_int cols;
  opt "--microns-per-cell" string_of_float microns_per_cell;
  add "--format" format;
  add "--dpi" (string_of_int dpi);
  add "--size" (string_of_float size);
  add "--alpha" (string_of_float alpha);
  opt "--first" string_of_int first;
  opt "--last" string_of_int last;
  add "--step" (string_of_int step);
  let argv = Array.of_list !args in
  let pid = Unix.create_process python argv Unix.stdin Unix.stdout Unix.stderr in
  let _, status = Unix.waitpid [] pid in
  match status with
  | Unix.WEXITED 0 -> ()
  | Unix.WEXITED n -> failwith (Printf.sprintf "Plot.render_xml: Python exited with status %d" n)
  | Unix.WSIGNALED n -> failwith (Printf.sprintf "Plot.render_xml: Python killed by signal %d" n)
  | Unix.WSTOPPED n -> failwith (Printf.sprintf "Plot.render_xml: Python stopped by signal %d" n)
