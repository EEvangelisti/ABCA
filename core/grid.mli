type coord = {
  row : int;
  col : int;
}
(** Coordinate in the grid, using zero-based row and column indices. *)

type topology =
  | Bounded
  | Toroidal
(** Grid topology.
    [Bounded] rejects coordinates outside the grid.
    [Toroidal] wraps coordinates around grid edges. *)

type t
(** Opaque grid type. *)

val create :
  ?topology:topology ->
  rows:int ->
  cols:int ->
  unit ->
  t
(** Creates a grid with the given number of rows and columns.
    The default topology is [Bounded].
    Raises [Invalid_argument] if [rows] or [cols] is not positive. *)

val rows : t -> int
(** Returns the number of rows. *)

val cols : t -> int
(** Returns the number of columns. *)

val topology : t -> topology
(** Returns the grid topology. *)

val size : t -> int
(** Returns the total number of cells. *)

val valid : t -> coord -> bool
(** Returns [true] if a coordinate lies inside the grid bounds. *)

val normalize : t -> coord -> coord option
(** Normalizes a coordinate according to the grid topology.
    For bounded grids, returns [None] if the coordinate is outside the grid.
    For toroidal grids, wraps the coordinate and always returns [Some]. *)

val index : t -> coord -> int
(** Converts a coordinate into a linear index.
    In toroidal grids, coordinates are wrapped before indexing.
    Raises [Invalid_argument] for out-of-bounds coordinates in bounded grids. *)

val coord : t -> int -> coord
(** Converts a linear index into a coordinate.
    Raises [Invalid_argument] if the index is outside the grid. *)

val iter_coords : t -> (coord -> unit) -> unit
(** Iterates over all grid coordinates in row-major order. *)

val fold_coords : t -> 'a -> ('a -> coord -> 'a) -> 'a
(** Folds over all grid coordinates in row-major order. *)

val map_coords : t -> (coord -> 'a) -> 'a array array
(** Builds a two-dimensional array by applying a function to each coordinate. *)

val moore_offsets : coord array
(** Relative offsets of the eight Moore neighbors. *)

val von_neumann_offsets : coord array
(** Relative offsets of the four von Neumann neighbors. *)

val add : coord -> coord -> coord
(** Adds two coordinates component-wise. *)

val moore_neighbors : t -> coord -> coord list
(** Returns the valid Moore neighbors of a coordinate.
    In toroidal grids, neighbors are wrapped around the edges. *)

val von_neumann_neighbors : t -> coord -> coord list
(** Returns the valid von Neumann neighbors of a coordinate.
    In toroidal grids, neighbors are wrapped around the edges. *)

val distance2 : coord -> coord -> int
(** Returns the squared Euclidean distance between two coordinates. *)

val manhattan_distance : coord -> coord -> int
(** Returns the Manhattan distance between two coordinates. *)
