(*
 * ABCA (Agent-Based Cellular Automata)
 * A modular simulation framework for discrete spatial systems,
 * ranging from classical cellular automata to biologically inspired
 * agent-based models.
 *
 * Copyright (c) 2026 Edouard Evangelisti
 *
 * Distributed under the MIT License.
 * This software is provided "as is", without warranty of any kind.
 * See the LICENSE file for details.
 *)

type coord = {
  row : int;
  col : int;
}

type topology =
  | Bounded
  | Toroidal

type t = {
  rows     : int;
  cols     : int;
  topology : topology;
}

let create ?(topology = Bounded) ~rows ~cols () =
  if rows <= 0 then invalid_arg "Grid.create: rows must be positive";
  if cols <= 0 then invalid_arg "Grid.create: cols must be positive";
  { rows; cols; topology }

let rows g = g.rows

let cols g = g.cols

let topology g = g.topology

let size g =
  g.rows * g.cols

let valid g { row; col } =
  row >= 0 && row < g.rows && col >= 0 && col < g.cols

let wrap_index n i =
  ((i mod n) + n) mod n

let normalize g { row; col } =
  match g.topology with
  | Bounded ->
      if valid g { row; col } then Some { row; col } else None
  | Toroidal ->
      Some {
        row = wrap_index g.rows row;
        col = wrap_index g.cols col;
      }

let index g { row; col } =
  match normalize g { row; col } with
  | None ->
      invalid_arg "Grid.index: coordinate outside bounded grid"
  | Some { row; col } ->
      row * g.cols + col

let coord g i =
  if i < 0 || i >= size g then
    invalid_arg "Grid.coord: index outside grid";
  {
    row = i / g.cols;
    col = i mod g.cols;
  }

let iter_coords g f =
  for row = 0 to g.rows - 1 do
    for col = 0 to g.cols - 1 do
      f { row; col }
    done
  done

let fold_coords g init f =
  let acc = ref init in
  iter_coords g (fun c ->
      acc := f !acc c);
  !acc

let map_coords g f =
  Array.init g.rows (fun row ->
      Array.init g.cols (fun col ->
          f { row; col }))

let moore_offsets =
  [|
    { row = -1; col = -1 };
    { row = -1; col =  0 };
    { row = -1; col =  1 };
    { row =  0; col = -1 };
    { row =  0; col =  1 };
    { row =  1; col = -1 };
    { row =  1; col =  0 };
    { row =  1; col =  1 };
  |]

let von_neumann_offsets =
  [|
    { row = -1; col =  0 };
    { row =  0; col = -1 };
    { row =  0; col =  1 };
    { row =  1; col =  0 };
  |]

let add a b =
  {
    row = a.row + b.row;
    col = a.col + b.col;
  }

let neighbors_from_offsets g offsets c =
  offsets
  |> Array.to_list
  |> List.filter_map (fun d -> normalize g (add c d))

let moore_neighbors g c =
  neighbors_from_offsets g moore_offsets c

let von_neumann_neighbors g c =
  neighbors_from_offsets g von_neumann_offsets c

let distance2 a b =
  let dr = a.row - b.row in
  let dc = a.col - b.col in
  (dr * dr) + (dc * dc)

let manhattan_distance a b =
  abs (a.row - b.row) + abs (a.col - b.col)
