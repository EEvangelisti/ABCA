(* ABCA - PNG rendering utilities. MIT License, (c) 2026 Edouard Evangelisti. *)
type color = float * float * float
(** RGB components in [0,1]. *)
type palette = { background : color; colors : color array }
val default_palette : palette
val save_frame :
  filename:string -> cell_size:int -> ?background:color ->
  palette:palette -> to_color_index:('state -> int option) ->
  'state array array -> unit
(** Render one square-cell grid as a PNG, without antialiasing. *)
val save_frames :
  dirname:string -> prefix:string -> every:int -> cell_size:int ->
  ?background:color -> palette:palette ->
  to_color_index:('state -> int option) -> 'state array array array -> unit
(** Render selected grid frames as numbered PNG files. *)
