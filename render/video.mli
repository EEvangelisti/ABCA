val make_gif :
  ?log_file:string ->
  fps:int ->
  png_dir:string ->
  prefix:string ->
  output:string ->
  unit -> unit

val make_mp4 :
  ?log_file:string ->
  fps:int ->
  png_dir:string ->
  prefix:string ->
  output:string -> 
  unit -> unit
