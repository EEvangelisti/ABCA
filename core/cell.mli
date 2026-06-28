(* cell.mli *)

type state = int

type flags = {
  active  : bool;
  dirty   : bool;
  blocked : bool;
}

type metadata = (string * string) list

type t

val empty : t

val create :
  ?active:bool ->
  ?dirty:bool ->
  ?blocked:bool ->
  ?metadata:metadata ->
  state ->
  t

val state : t -> state

val flags : t -> flags

val metadata : t -> metadata

val is_empty : t -> bool

val is_active : t -> bool

val is_dirty : t -> bool

val is_blocked : t -> bool

val with_state : state -> t -> t

val with_flags : flags -> t -> t

val with_metadata : metadata -> t -> t

val set_active : bool -> t -> t

val set_dirty : bool -> t -> t

val set_blocked : bool -> t -> t

val add_metadata : string -> string -> t -> t

val remove_metadata : string -> t -> t

val metadata_opt : string -> t -> string option

val clear_metadata : t -> t

val equal : t -> t -> bool
