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
    (0.800000, 0.400000, 0.466667);  (* #CC6677 — rose *)
    (0.200000, 0.133333, 0.533333);  (* #332288 — indigo *)
    (0.866667, 0.800000, 0.466667);  (* #DDCC77 — sand *)
    (0.066667, 0.466667, 0.200000);  (* #117733 — green *)
    (0.533333, 0.800000, 0.933333);  (* #88CCEE — cyan *)
    (0.533333, 0.133333, 0.333333);  (* #882255 — wine *)
    (0.266667, 0.666667, 0.600000);  (* #44AA99 — teal *)
    (0.600000, 0.600000, 0.200000);  (* #999933 — olive *)
    (0.666667, 0.266667, 0.600000);  (* #AA4499 — purple *)
  |]

include Template.Make(struct
  let name = "tol-muted"
  let description = "Paul Tol Muted qualitative colour scheme."
  let background = (1.,1.,1.)
  let control_points = control_points
end)
