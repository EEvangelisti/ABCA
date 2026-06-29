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
    (0.267,0.005,0.329);
    (0.283,0.141,0.458);
    (0.254,0.265,0.530);
    (0.207,0.372,0.553);
    (0.164,0.471,0.558);
    (0.128,0.567,0.551);
    (0.369,0.789,0.383);
    (0.993,0.906,0.144);
  |]

include Template.Make(struct
  let name = "viridis"
  let description = "Matplotlib Viridis perceptually uniform colour map."
  let background = (1.,1.,1.)
  let control_points = control_points
end)
