(* rng.mli *)

type t

val create : int -> t

val seed : t -> int

val copy : t -> t

val int : t -> int -> int

val float : t -> float -> float

val bool : t -> bool

val chance : t -> float -> bool

val range_int : t -> min:int -> max:int -> int

val range_float : t -> min:float -> max:float -> float

val choose : t -> 'a array -> 'a

val shuffle_array : t -> 'a array -> unit
