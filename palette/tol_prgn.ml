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
 * Paul Tol PRGn diverging colour scheme.
 *
 * The palette follows the print-friendly PRGn variant described by
 * Paul Tol, in which #A6DBA0 is replaced by #ACD39E.
 *)
let control_points =
  [|
    (0.462745, 0.164706, 0.513725);  (* #762A83 — dark purple *)
    (0.600000, 0.439216, 0.670588);  (* #9970AB — purple *)
    (0.760784, 0.647059, 0.811765);  (* #C2A5CF — light purple *)
    (0.905882, 0.831373, 0.909804);  (* #E7D4E8 — pale purple *)
    (0.968627, 0.968627, 0.968627);  (* #F7F7F7 — neutral grey *)
    (0.850980, 0.941176, 0.827451);  (* #D9F0D3 — pale green *)
    (0.674510, 0.827451, 0.619608);  (* #ACD39E — light green *)
    (0.352941, 0.682353, 0.380392);  (* #5AAE61 — green *)
    (0.105882, 0.470588, 0.215686);  (* #1B7837 — dark green *)
  |]

include Template.Make(struct
  let name = "tol-prgn"
  let description =
    "Paul Tol PRGn diverging colour scheme (print-friendly variant)."
  let background = (1., 1., 1.)
  let control_points = control_points
end)
