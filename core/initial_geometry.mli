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

val select :
  Grid.t ->
  shape ->
  Grid.coord array

val random_subset :
  Rng.t ->
  n:int ->
  Grid.coord array ->
  Grid.coord array
