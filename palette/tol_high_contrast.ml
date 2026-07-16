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
    (0.000000, 0.266667, 0.533333);  (* #004488 — blue *)
    (0.866667, 0.666667, 0.200000);  (* #DDAA33 — yellow *)
    (0.733333, 0.333333, 0.400000);  (* #BB5566 — red *)
  |]

include Template.Make(struct
  let name = "tol-high-contrast"
  let description = "Paul Tol High-contrast qualitative colour scheme."
  let background = (1.,1.,1.)
  let control_points = control_points
end)
