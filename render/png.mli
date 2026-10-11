(* ABCA - PNG rendering utilities. MIT License, (c) 2026 Edouard Evangelisti. *)
type color = float * float * float
(** RGB components in [0,1]. *)

type palette = { background : color; colors : color array }
val default_palette : palette

type point_style = {
  radius : float;        (** Dot radius in output pixels. *)
  alpha : float;         (** Opacity in [0,1]. *)
  antialias : bool;      (** Smooth circular dots. *)
  multiplicity : bool;   (** Count grids: combine opacity for overlapping agents. *)
}
val default_point_style : point_style

val save_frame :
  filename:string -> cell_size:int -> ?background:color ->
  palette:palette -> to_color_index:('state -> int option) ->
  'state array array -> unit
(** Backwards-compatible dual export: writes the original square-cell PNG
    at [filename], plus an antialiased dot image at [*_points.png].
    No change to existing callers is needed. *)

val save_frames :
  dirname:string -> prefix:string -> every:int -> cell_size:int ->
  ?background:color -> palette:palette ->
  to_color_index:('state -> int option) -> 'state array array array -> unit
(** Backwards-compatible dual export for every selected frame.
    Each numbered square PNG gets a matching [_points.png] file. *)

val save_point_frame :
  filename:string -> cell_size:int -> ?background:color ->
  palette:palette -> to_color_index:('state -> int option) ->
  ?style:point_style -> 'state array array -> unit
(** One smooth circular dot per nonempty grid cell. Does not infer agent
    multiplicity from a generic cell state. *)

val save_point_frames :
  dirname:string -> prefix:string -> every:int -> cell_size:int ->
  ?background:color -> palette:palette ->
  to_color_index:('state -> int option) -> ?style:point_style ->
  'state array array array -> unit
(** Numbered smooth-dot snapshots of generic grid frames. *)

val save_count_frame :
  filename:string -> cell_size:int -> ?background:color ->
  ?color:color -> ?style:point_style -> int array array -> unit
(** Draw count grids. A cell with n agents is one dot whose opacity is
    1-(1-alpha)^n when [style.multiplicity=true]. Counts must be >=0.
    This preserves density visually but does not resolve distinct positions
    inside the same cell. *)

val save_xy_points :
  filename:string -> rows:int -> cols:int -> cell_size:int ->
  ?background:color -> ?color:color -> ?style:point_style ->
  (float * float) array -> unit
(** Draw one dot per agent at continuous coordinates in GRID CELL units.
    Coordinates are multiplied by [cell_size]; points outside the domain
    are omitted. For micrometre coordinates, divide by micrometres/cell
    before calling. Use this for a Matplotlib-scatter-like rendering. *)
