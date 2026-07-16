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
 

(* This module defines the simulation parameters and the public entry point
 * of the empirical zoospore movement model.
 *
 * Biological movement parameters, including the complete latent VAR(1)
 * matrices A, Q and R, are loaded from abca_local_parameters.csv.
 * No global trajectory statistic, such as mean squared displacement,
 * straightness, tortuosity or net displacement, is imposed on the agents.
 *
 * Distributional assumptions are documented in
 * zoospores_empirical_assumptions.md.
 *)

(** Integer state used to encode the simulated grid.

    The integer representation is exposed because it is required by the
    ABCA binary codecs and output infrastructure. *)
type state = int

(** Spatial distribution used to initialise the zoospore population. *)
type init_shape =
  | Init_full
      (** Agents are distributed across the entire simulation domain. *)
  | Init_disk
      (** Agents are distributed uniformly inside a centred disk. *)
  | Init_ring
      (** Agents are distributed inside a centred annulus. *)

(** Complete set of parameters required to run a simulation.

    This record combines empirically calibrated biological parameters with
    simulation-specific settings supplied through the ABCA command line. *)
type params = {
  empirical : Zoospore_empirical_data.empirical;
      (** Empirically inferred parameters governing zoospore motion. *)

  parameter_file : string;
      (** Path to the file containing the calibrated model parameters. *)

  quantile_file : string;
      (** Path to the file containing the empirical quantile distributions. *)

  agents : int;
      (** Number of zoospore agents included in the simulation. *)

  init_shape : init_shape;
      (** Spatial distribution used to initialise the agents. *)

  radius : float;
      (** Radius of the initial disk or ring, expressed in grid cells. *)

  thickness : float;
      (** Thickness of the initial ring, expressed in grid cells. *)

  microns_per_cell : float;
      (** Physical size represented by one grid cell, in micrometres. *)

  max_age : int;
      (** Maximum displayed agent age before its visual state is reset. *)

  accel_cap_multiplier : float;
      (** Multiplier applied to the empirical acceleration threshold. *)

  seed : int;
      (** Seed used to initialise the pseudo-random number generator. *)

  topology : Abca.Grid.topology;
      (** Boundary topology of the simulation grid. *)
}

(** [parse_init_shape value] converts a textual initialisation mode into its
    corresponding {!init_shape} value.

    The comparison is case-insensitive. An exception is raised when [value]
    does not identify a supported initialisation mode. *)
val parse_init_shape :
  string -> init_shape

(** [string_of_init_shape shape] returns the canonical textual representation
    of [shape]. *)
val string_of_init_shape :
  init_shape -> string

(** [simulate params grid generations] runs the empirical zoospore model.

    Agents are initialised according to [params.init_shape] and subsequently
    updated for the requested number of [generations]. At each time step, their
    RUN or STOP state, latent kinematic variables, speed, turning angle and
    spatial position are updated from the calibrated empirical model.

    The function returns:

    - the complete sequence of grid frames;
    - the corresponding per-agent trajectory records.

    The initial grid provides the simulation dimensions and boundary
    topology, while the physical and biological behaviour is controlled by
    [params]. *)
val simulate :
  params ->
  Abca.Grid.t ->
  int ->
  int array array array * Abca_io.Agent_trace.record array
