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
    (0.000,0.135,0.305);
    (0.000,0.227,0.418);
    (0.153,0.313,0.452);
    (0.310,0.397,0.430);
    (0.471,0.486,0.377);
    (0.637,0.581,0.298);
    (0.809,0.690,0.183);
    (0.996,0.909,0.218);
  |]

include Template.Make(struct
  let name = "cividis"
  let description = "Matplotlib Cividis perceptually uniform colour map, designed to be colour-vision-deficiency friendly."
  let background = (1.,1.,1.)
  let control_points = control_points
end)
