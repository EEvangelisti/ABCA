(* io_binary.mli *)

module type STATE_CODEC = sig
  type t

  val to_int32 : t -> int32
  val of_int32 : int32 -> t
end

type header = {
  version    : int;
  rows       : int;
  cols       : int;
  generation : int;
  frames     : int;
  metadata   : Metadata.t;
}

val save_frames :
  filename:string ->
  grid:Abca.Grid.t ->
  generation:int ->
  metadata:Metadata.t ->
  frames:'state array array array ->
  codec:(module STATE_CODEC with type t = 'state) ->
  unit

val load_frames :
  filename:string ->
  codec:(module STATE_CODEC with type t = 'state) ->
  header * 'state array array array
