val make_gif :
  ?log_file:string ->
  fps:int ->
  png_dir:string ->
  prefix:string ->
  output:string ->
  unit -> unit
(** Creates an animated GIF from a sequence of PNG images using FFmpeg.
    Input images must be named ["<prefix>_000001.png"], ["<prefix>_000002.png"], etc.
    A temporary palette is generated automatically to improve image quality.
    Raises [Invalid_argument] if [fps] is not positive.
    Terminates the program if an FFmpeg command fails. *)

val make_mp4 :
  ?log_file:string ->
  fps:int ->
  png_dir:string ->
  prefix:string ->
  output:string ->
  unit -> unit
(** Creates an MP4 video from a sequence of PNG images using FFmpeg.
    Input images must be named ["<prefix>_000001.png"], ["<prefix>_000002.png"], etc.
    The output is encoded with H.264 using the YUV420P pixel format for
    broad compatibility.
    Raises [Invalid_argument] if [fps] is not positive.
    Terminates the program if an FFmpeg command fails. *)
