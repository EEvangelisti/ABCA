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

let clamp01 x =
  max 0.0 (min 1.0 x)

let make ~states =
  let states =
    max 1 states
  in

  let colors =
    Array.init states (fun i ->
        if i = 0 then
          (0.0, 0.0, 0.0)
        else begin
          let x =
            float i /. float (max 1 (states - 1))
          in

          let r =
            clamp01 (3.0 *. x)
          in
          let g =
            clamp01 (3.0 *. x -. 1.0)
          in
          let b =
            clamp01 (3.0 *. x -. 2.0)
          in

          (r, g, b)
        end)
  in

  {
    Abca_render.Png.background = (0.0, 0.0, 0.0);
    colors;
  }

let generator =
  {
    Register.name = "heat";
    description = "Black-red-yellow-white heat palette.";
    make;
  }
