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

let control_points =
  [|
    (0.266667, 0.466667, 0.666667);  (* #4477AA — blue *)
    (0.933333, 0.400000, 0.466667);  (* #EE6677 — red *)
    (0.133333, 0.533333, 0.200000);  (* #228833 — green *)
    (0.800000, 0.733333, 0.266667);  (* #CCBB44 — yellow *)
    (0.400000, 0.800000, 0.933333);  (* #66CCEE — cyan *)
    (0.666667, 0.200000, 0.466667);  (* #AA3377 — purple *)
    (0.733333, 0.733333, 0.733333);  (* #BBBBBB — grey *)
  |]

include Template.Make(struct
  let name = "tol-bright"
  let description = "Paul Tol Bright qualitative colour scheme."
  let background = (1.,1.,1.)
  let control_points = control_points
end)
