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

module type SPEC = sig
  val name : string
  val description : string
  val background : Abca_render.Png.color
  val control_points : Abca_render.Png.color array
end

module Make (Spec : SPEC) = struct
  let lerp a b t =
    a +. t *. (b -. a)

  let lerp_color (r1, g1, b1) (r2, g2, b2) t =
    (
      lerp r1 r2 t,
      lerp g1 g2 t,
      lerp b1 b2 t
    )

  let sample t =
    let n =
      Array.length Spec.control_points
    in

    if n = 0 then
      invalid_arg "Palette.Template: empty control point array";

    if t <= 0.0 then
      Spec.control_points.(0)

    else if t >= 1.0 then
      Spec.control_points.(n - 1)

    else begin
      let x =
        t *. float (n - 1)
      in

      let i =
        int_of_float x
      in

      let u =
        x -. float i
      in

      lerp_color
        Spec.control_points.(i)
        Spec.control_points.(i + 1)
        u
    end

  let make ~states =
    let states =
      max 1 states
    in

    let colors =
      Array.init states (fun i ->
          sample
            (float i /. float (max 1 (states - 1))))
    in

    {
      Abca_render.Png.background = Spec.background;
      colors;
    }

  let generator =
    {
      Register.name = Spec.name;
      description = Spec.description;
      make;
    }
end
