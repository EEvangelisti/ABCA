type t = (string * string) list

val empty : t

val add : string -> string -> t -> t

val get : string -> t -> string option

val of_list : (string * string) list -> t

val to_list : t -> (string * string) list

val to_json : t -> string

val of_json : string -> t
