(* io_xml.mli *)

module type STATE_CODEC = sig
  type t

  val to_string : t -> string
end

val save_frames :
  filename:string ->
  model:string ->
  grid:Abca.Grid.t ->
  generation:int ->
  frames:'state array array array ->
  codec:(module STATE_CODEC with type t = 'state) ->
  unit
