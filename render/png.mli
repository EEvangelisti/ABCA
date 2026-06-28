type color = float * float * float

type palette = {
  background : color;
  colors     : color array;
}

val default_palette : palette

val save_frame :
  filename:string ->
  cell_size:int ->
  ?background:color ->
  ?skip_index:int ->
  palette:palette ->
  to_color_index:('state -> int) ->
  'state array array ->
  unit

val save_frames :
  dirname:string ->
  prefix:string ->
  every:int ->
  cell_size:int ->
  ?background:color ->
  ?skip_index:int -> 
  palette:palette ->
  to_color_index:('state -> int) ->
  'state array array array ->
  unit
