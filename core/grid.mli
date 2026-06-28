type coord = {
  row : int;
  col : int;
}

type topology =
  | Bounded
  | Toroidal

type t

val create :
  ?topology:topology ->
  rows:int ->
  cols:int ->
  unit ->
  t

val rows : t -> int

val cols : t -> int

val topology : t -> topology

val size : t -> int

val valid : t -> coord -> bool

val normalize : t -> coord -> coord option

val index : t -> coord -> int

val coord : t -> int -> coord

val iter_coords : t -> (coord -> unit) -> unit

val fold_coords : t -> 'a -> ('a -> coord -> 'a) -> 'a

val map_coords : t -> (coord -> 'a) -> 'a array array

val moore_offsets : coord array

val von_neumann_offsets : coord array

val add : coord -> coord -> coord

val moore_neighbors : t -> coord -> coord list

val von_neumann_neighbors : t -> coord -> coord list

val distance2 : coord -> coord -> int

val manhattan_distance : coord -> coord -> int
