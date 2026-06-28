let control_points =
  [|
    (0.001,0.000,0.014);
    (0.124,0.016,0.262);
    (0.317,0.072,0.485);
    (0.523,0.134,0.507);
    (0.716,0.215,0.475);
    (0.902,0.364,0.322);
    (0.987,0.631,0.215);
    (0.987,0.991,0.750);
  |]

include Template.Make(struct
  let name = "magma"
  let description = "Matplotlib Magma perceptually uniform colour map."
  let background = (1.,1.,1.)
  let control_points = control_points
end)
