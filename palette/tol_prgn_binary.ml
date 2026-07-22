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
    (0.462745, 0.164706, 0.513725);  (* #762A83 — SLOW / state 0 *)
    (0.105882, 0.470588, 0.215686);  (* #1B7837 — FAST / state 1 *)
  |]

include Template.Make(struct
  let name = "tol-prgn-binary"
  let description =
    "Binary Paul Tol PRGn scheme: dark purple and dark green."
  let background = (1., 1., 1.)
  let control_points = control_points
end)
