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

(*
 * Binary form of Paul Tol's PRGn diverging colour scheme.
 *
 * State 0 is mapped to the dark-purple extreme and state 1 to the
 * dark-green extreme. This is intended for two-state models such as
 * SLOW/FAST zoospore behaviour.
 *)
let control_points =
  [|
    (0.482353, 0.686275, 0.870588);  (* #7BAFDE *)
    (0.909804, 0.635294, 0.109804);  (* #E8A21C *)
  |]

include Template.Make(struct
  let name = "python-binary"
  let description =
    "Binary Python-like scheme: light blue and yellow."
  let background = (1., 1., 1.)
  let control_points = control_points
end)
