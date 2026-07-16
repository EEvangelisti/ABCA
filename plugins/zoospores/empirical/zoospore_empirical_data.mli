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


type quantile_dist

type empirical = {
  dt : float;
  initial_run_fraction : float;
  p_run_run : float;
  p_run_stop : float;
  p_stop_stop : float;
  p_stop_run : float;
  a11 : float;
  a12 : float;
  a21 : float;
  a22 : float;
  q11 : float;
  q12 : float;
  q22 : float;
  r11 : float;
  r12 : float;
  r22 : float;
  positive_turn_probability : float;
  negative_turn_probability : float;
  absolute_acceleration_q90 : float;
  default_accel_cap_multiplier : float;
  default_microns_per_cell : float;
  run_speed : quantile_dist;
  stop_speed : quantile_dist;
  abs_turn : quantile_dist;
}


val default_parameter_file : string
val quantile_file_from_parameter_file : string -> string

val load_empirical : string -> string -> empirical

val quantile : quantile_dist -> float -> float

val normal_cdf : float -> float

val inverse_normal_cdf : float -> float

val validate_latent_var1 : empirical -> unit
