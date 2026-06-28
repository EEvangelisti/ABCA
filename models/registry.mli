exception Unknown_model of string

val register : Model.t -> unit

val find : string -> Model.t

val exists : string -> bool

val all : unit -> Model.t list

val by_family : Model.family -> Model.t list

val families : unit -> Model.family list

val names : unit -> string list
