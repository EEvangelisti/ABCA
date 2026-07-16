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

(** Empirical quantile distribution.

    A quantile distribution represents an experimental cumulative
    distribution function (CDF) sampled from biological measurements.
    It is used to convert uniformly distributed probabilities into
    empirical values by interpolation, thereby preserving the observed
    marginal distributions of zoospore kinematic variables. *)
type quantile_dist

(** Complete set of empirical parameters describing zoospore motion.

    This record gathers all quantities inferred from experimental
    trajectory data and required to simulate the empirical zoospore
    model.

    It includes:

    - the temporal resolution of the acquisition;
    - the RUN/STOP Markov transition probabilities;
    - the latent VAR(1) model parameters (A, Q and R);
    - turning direction probabilities;
    - default simulation parameters;
    - empirical quantile distributions for speed and turning angle.

    The record is loaded once at the beginning of a simulation and is
    subsequently treated as read-only. *)
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

(** Default location of the CSV file containing the calibrated
    biological parameters. *)
val default_parameter_file : string

(** Returns the default quantile file associated with a given
    parameter file. *)
val quantile_file_from_parameter_file : string -> string

(** Loads the complete empirical model from the parameter and
    quantile CSV files.

    The function performs consistency checks and raises an exception
    if mandatory parameters are missing or malformed. *)
val load_empirical : string -> string -> empirical

(** Evaluates an empirical quantile distribution by linear
    interpolation.

    The input probability is expected to lie in the interval [0,1].
    Values outside this range are clamped before interpolation. *)
val quantile : quantile_dist -> float -> float

(** Standard normal cumulative distribution function. *)
val normal_cdf : float -> float

(** Inverse of the standard normal cumulative distribution function.

    This function maps a probability in [0,1] onto the corresponding
    standard Gaussian quantile and is used by the Gaussian copula
    underlying the latent VAR(1) model. *)
val inverse_normal_cdf : float -> float

(** Verifies that the latent VAR(1) process is dynamically stable.

    The function checks that the eigenvalues of the transition matrix
    satisfy the stationarity condition required for the simulation.
    An exception is raised if the model is unstable. *)
val validate_latent_var1 : empirical -> unit
