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

(** This module provides small mathematical utility functions shared by
  * several components of the empirical zoospore model. *)

(** [clamp lo hi x] restricts [x] to the closed interval [[lo, hi]].
    Values smaller than [lo] are replaced by [lo], whereas values
    larger than [hi] are replaced by [hi]. *)
val clamp : float -> float -> float -> float

(** [clamp01 x] restricts [x] to the unit interval [[0.0, 1.0]].
    This helper is primarily used for probabilities and quantiles. *)
val clamp01 : float -> float
