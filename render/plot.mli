(** Scientific spatial plots from ABCA particle/detection XML files.
    Requires Python 3, Matplotlib, and render_abca_frames.py.
    Uses Unix.create_process (no shell interpolation). *)
val render_xml :
  ?python:string -> ?script:string -> ?outdir:string ->
  ?width:float -> ?height:float ->
  ?rows:int -> ?cols:int -> ?microns_per_cell:float ->
  ?format:string -> ?dpi:int -> ?size:float -> ?alpha:float ->
  ?first:int -> ?last:int -> ?step:int ->
  xml:string -> unit -> unit
(** Generate one plot per XML generation. Raises Failure if Python fails.
    Explicit dimensions are recommended for comparable spatial scales. *)
