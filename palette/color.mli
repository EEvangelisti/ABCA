type t = Abca_render.Png.color

val black : t
val white : t
val red : t
val green : t
val blue : t
val yellow : t
val orange : t
val gray : t

val of_name : string -> t option
val of_hex : string -> t option
val parse : string -> t

val to_string : t -> string
