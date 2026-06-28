let control_points =
  [|
    (0.001,0.000,0.014);
    (0.145,0.039,0.329);
    (0.341,0.063,0.429);
    (0.549,0.161,0.506);
    (0.735,0.284,0.441);
    (0.902,0.425,0.271);
    (0.986,0.673,0.117);
    (0.988,0.998,0.645);
  |]

include Template.Make(struct
  let name = "inferno"
  let description = "Matplotlib Inferno perceptually uniform colour map."
  let background = (1.,1.,1.)
  let control_points = control_points
end)
