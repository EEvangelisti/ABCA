type shape =
  | Full_grid
  | Disk of {
      center : Grid.coord option;
      radius : float;
    }
  | Ring of {
      center    : Grid.coord option;
      radius    : float;
      thickness : float;
    }

let default_center grid =
  {
    Grid.row = Grid.rows grid / 2;
    col = Grid.cols grid / 2;
  }

let distance a b =
  let dr =
    float (a.Grid.row - b.Grid.row)
  in
  let dc =
    float (a.Grid.col - b.Grid.col)
  in
  sqrt ((dr *. dr) +. (dc *. dc))

let select grid shape =
  let coords =
    ref []
  in

  let keep =
    match shape with
    | Full_grid ->
        fun _ -> true

    | Disk { center; radius } ->
        let center =
          Option.value center ~default:(default_center grid)
        in
        fun coord ->
          distance coord center <= radius

    | Ring { center; radius; thickness } ->
        let center =
          Option.value center ~default:(default_center grid)
        in
        let half =
          thickness /. 2.0
        in
        fun coord ->
          let d =
            distance coord center
          in
          d >= radius -. half && d <= radius +. half
  in

  Grid.iter_coords grid
    (fun coord ->
       if keep coord then
         coords := coord :: !coords);

  Array.of_list !coords

let random_subset rng ~n coords =
  let coords =
    Array.copy coords
  in

  Rng.shuffle_array rng coords;

  let n =
    min n (Array.length coords)
  in

  Array.sub coords 0 n
