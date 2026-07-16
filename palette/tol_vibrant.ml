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
    (0.933333, 0.466667, 0.200000);  (* #EE7733 — orange *)
    (0.000000, 0.466667, 0.733333);  (* #0077BB — blue *)
    (0.200000, 0.733333, 0.933333);  (* #33BBEE — cyan *)
    (0.933333, 0.200000, 0.466667);  (* #EE3377 — magenta *)
    (0.800000, 0.200000, 0.066667);  (* #CC3311 — red *)
    (0.000000, 0.600000, 0.533333);  (* #009988 — teal *)
    (0.733333, 0.733333, 0.733333);  (* #BBBBBB — grey *)
  |]

include Template.Make(struct
  let name = "tol-vibrant"
  let description = "Paul Tol Vibrant qualitative colour scheme."
  let background = (1.,1.,1.)
  let control_points = control_points
end)
