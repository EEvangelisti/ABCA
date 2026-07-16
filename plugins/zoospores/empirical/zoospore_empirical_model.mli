(*
 * Empirical zoospore plugin for ABCA.
 *
 * Biological movement parameters, including the complete latent VAR(1)
 * matrices A, Q and R, are loaded from abca_local_parameters.csv.
 * No global trajectory statistic (MSD,
 * straightness, tortuosity or net displacement) is imposed.
 *
 * Distributional assumptions are documented in
 * zoospores_empirical_assumptions.md.
 *)
 
type state = int
 
type init_shape =
  | Init_full
  | Init_disk
  | Init_ring

type params = {
  empirical : Zoospore_empirical_data.empirical;
  parameter_file : string;
  quantile_file : string;
  agents : int;
  init_shape : init_shape;
  radius : float;
  thickness : float;
  microns_per_cell : float;
  max_age : int;
  accel_cap_multiplier : float;
  seed : int;
  topology : Abca.Grid.topology;
}

val parse_init_shape :
  string -> init_shape

val string_of_init_shape : init_shape -> string

val simulate :
  params ->
  Abca.Grid.t ->
  int ->
  int array array array * Abca_io.Agent_trace.record array
