type t
(** Pseudorandom number generator with an immutable seed and mutable state. *)

val create : int -> t
(** Creates a new generator initialized with the given seed. *)

val seed : t -> int
(** Returns the initial seed used to create the generator. *)

val copy : t -> t
(** Returns an independent copy of the generator preserving its current state. *)

val int : t -> int -> int
(** Returns a random integer in the range [[0, bound)].
    Raises [Invalid_argument] if [bound <= 0]. *)

val float : t -> float -> float
(** Returns a random floating-point value in the range [[0.0, bound)].
    Raises [Invalid_argument] if [bound <= 0.0]. *)

val bool : t -> bool
(** Returns a random Boolean value. *)

val chance : t -> float -> bool
(** Returns [true] with probability [p].
    Raises [Invalid_argument] if [p] is not between [0.0] and [1.0]. *)

val range_int : t -> min:int -> max:int -> int
(** Returns a random integer in the inclusive range [[min, max]].
    Raises [Invalid_argument] if [max < min]. *)

val range_float : t -> min:float -> max:float -> float
(** Returns a random floating-point value in the range [[min, max)].
    Raises [Invalid_argument] if [max < min]. *)

val choose : t -> 'a array -> 'a
(** Returns a uniformly chosen element from an array.
    Raises [Invalid_argument] if the array is empty. *)

val shuffle_array : t -> 'a array -> unit
(** Randomly shuffles an array in place using the Fisher–Yates algorithm. *)
