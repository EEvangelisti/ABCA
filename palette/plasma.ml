let control_points =
  [|
    (0.050,0.030,0.528);
    (0.293,0.010,0.629);
    (0.507,0.027,0.654);
    (0.695,0.165,0.564);
    (0.841,0.333,0.427);
    (0.942,0.520,0.290);
    (0.991,0.709,0.184);
    (0.940,0.975,0.131);
  |]

include Template.Make(struct
  let name = "plasma"
  let description = "Matplotlib Plasma perceptually uniform colour map."
  let background = (1.,1.,1.)
  let control_points = control_points
end)
