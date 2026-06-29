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

let tau =
  6.283185307179586

let clamp01 x =
  max 0.0 (min 1.0 x)

let make ~states =
  let states =
    max 1 states
  in

  let colors =
    Array.init states (fun i ->
        let x =
          float i /. float states
        in

        let r =
          0.5 +. 0.5 *. sin (tau *. x)
        in
        let g =
          0.5 +. 0.5 *. sin (tau *. (x +. (1.0 /. 3.0)))
        in
        let b =
          0.5 +. 0.5 *. sin (tau *. (x +. (2.0 /. 3.0)))
        in

        (clamp01 r, clamp01 g, clamp01 b))
  in

  {
    Abca_render.Png.background = (0.0, 0.0, 0.0);
    colors;
  }

let generator =
  {
    Register.name = "cyclic";
    description = "Smooth cyclic RGB palette for cyclic automata.";
    make;
  }
