let clamp01 x =
  max 0.0 (min 1.0 x)

let make ~states =
  let states =
    max 1 states
  in

  let colors =
    Array.init states (fun i ->
        let x =
          float i /. float (max 1 (states - 1))
        in
        let v =
          clamp01 x
        in
        (v, v, v))
  in

  {
    Abca_render.Png.background = (0.0, 0.0, 0.0);
    colors;
  }

let generator =
  {
    Register.name = "grayscale";
    description = "Linear grayscale palette, from black to white.";
    make;
  }
