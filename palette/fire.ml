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
        else if i = 1 then
          (1.0, 1.0, 1.0)
        else begin
          let x =
            float (i - 2) /. float (max 1 (states - 3))
          in

          let r =
            1.0
          in
          let g =
            clamp01 (1.0 -. x)
          in
          let b =
            0.0
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
    Register.name = "fire";
    description = "White active state followed by yellow-to-red ageing states.";
    make;
  }
