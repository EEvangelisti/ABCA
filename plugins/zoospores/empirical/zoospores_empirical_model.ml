(*
 * Empirical zoospore plugin for ABCA.
 *
 * Biological movement parameters, including the complete latent VAR(1)
 * matrices A, Q and R, are loaded from abca_local_parameters.csv.
 * No global trajectory statistic (MSD,
 * straightness, tortuosity or net displacement) is imposed.
 *
 * Distributional assumptions are documented in
 * zoospores_empirical_assumptions.md.
 *)

open Abca
module Data = Zoospores_empirical_data
module Utils = Zoospores_empirical_utils

type state = int
(* 0 = empty; 1 = SLOW; 2 = FAST *)

type motion_state = SLOW | FAST

type init_shape =
  | Init_full
  | Init_disk
  | Init_ring

type params = {
  empirical : Data.empirical;
  parameter_file : string;
  quantile_file : string;
  agents : int;
  init_shape : init_shape;
  radius : float;
  thickness : float;
  microns_per_cell : float;
  max_age : int;
  accel_cap_multiplier : float;
  seed : int;
  topology : Grid.topology;
}

type agent = {
  id : int;
  x : float;
  y : float;
  age : int;
  heading_deg : float;
  speed_um_s : float;

  (* Latent standard-normal variables used by the Gaussian copulas. *)
  speed_z : float;
  turn_z : float;

  motion : motion_state;
}



(* GEOMETRIC FUNCTIONS AND UTILITIES **************************************** *)

let state_of_motion = function SLOW -> 1 | FAST -> 2
let state_of_agent ag = state_of_motion ag.motion

let row_of_agent ag = int_of_float (Float.floor ag.y)
let col_of_agent ag = int_of_float (Float.floor ag.x)
let coord_of_agent ag = { Grid.row = row_of_agent ag; col = col_of_agent ag }

let parse_init_shape s =
  match String.uppercase_ascii (String.trim s) with
  | "FULL" | "RANDOM" -> Init_full
  | "DISK" | "CIRCLE" -> Init_disk
  | "RING" -> Init_ring
  | other -> failwith ("Zoospore empirical: unknown INIT shape: " ^ other)

let string_of_init_shape = function
  | Init_full -> "full"
  | Init_disk -> "disk"
  | Init_ring -> "ring"

let geometry_of_params params =
  match params.init_shape with
  | Init_full -> Initial_geometry.Full_grid
  | Init_disk -> Initial_geometry.Disk { center = None; radius = params.radius }
  | Init_ring ->
      Initial_geometry.Ring {
        center = None;
        radius = params.radius;
        thickness = params.thickness;
      }

let wrap_coordinate size x =
  let s = float_of_int size in
  let y = mod_float x s in
  if y < 0.0 then y +. s else y

let reflected_heading rows cols x y heading =
  let h = ref heading in
  if x < 0.0 || x >= float_of_int cols then h := 180.0 -. !h;
  if y < 0.0 || y >= float_of_int rows then h := -. !h;
  Utils.normalize_degrees !h
  


(* INITIALIZATION FUNCTIONS ************************************************* *)

(** Draw a sample from the standard normal distribution.

    This implementation uses the classical Box-Muller transform to
    convert two independent uniform random numbers into a Gaussian
    variate with mean 0 and variance 1. The first uniform sample is
    clamped away from zero to avoid evaluating [log 0]. *)
let standard_normal rng =
  let u1 = max 1e-12 (Rng.float rng 1.0) in
  let u2 = Rng.float rng 1.0 in
  sqrt (-2.0 *. log u1) *. cos (2.0 *. Float.pi *. u2)


(** Generate a stratified sample of approximately uniform random
    numbers over the unit interval.

    The interval [0,1] is divided into [n] equal strata, and one
    midpoint sample is placed in each stratum:

      u_i = (i + 1/2) / n.

    The samples are then randomly permuted to remove any ordering
    while preserving the exact stratification. This approach provides
    more even coverage of the unit interval than independent uniform
    sampling and reduces Monte Carlo variability. *)
let stratified_uniforms rng n =
  if n <= 0 then [||]
  else begin
    let nf = float_of_int n in
    let values =
      Array.init n (fun i ->
          (* Midpoint stratification, exactly as documented:
             u_i = (i + 1/2) / N. *)
          (float_of_int i +. 0.5) /. nf)
    in
    Rng.shuffle_array rng values;
    values
  end


(** Generate the initial FAST/SLOW states of the simulated population.

    The requested initial FAST fraction is converted to an integer
    number of agents, rounded to the nearest value and clamped to the
    valid range. The resulting FAST and SLOW labels are then randomly
    permuted so that the prescribed population proportion is preserved
    without introducing any spatial ordering. *)
let initial_motion_states rng n initial_fast_fraction =
  let n_fast =
    int_of_float
      (Float.round
         (Utils.clamp01 initial_fast_fraction *. float_of_int n))
    |> min n
    |> max 0
  in
  let states =
    Array.init n (fun i -> if i < n_fast then FAST else SLOW)
  in
  Rng.shuffle_array rng states;
  states


(** Generate a standard normal random variable with a prescribed
    Pearson correlation to another standard normal variable.

    Given a standard normal variate [z1] and an independent standard
    normal variate [independent_z2], this function returns a new
    standard normal variate whose correlation with [z1] is [rho]. The
    requested correlation is clamped slightly inside [-1,1] to avoid
    numerical degeneracies. *)
let correlated_standard_normals rho z1 independent_z2 =
  let rho = Utils.clamp (-0.999999) 0.999999 rho in
  rho *. z1 +. sqrt (1.0 -. rho *. rho) *. independent_z2


let distribution_for_state empirical = function
  | FAST -> empirical.Data.fast_speed
  | SLOW -> empirical.Data.slow_speed


(** Construct the initial population of zoospore agents.

    Agent positions are sampled from the requested initial geometry,
    using the simulation seed for reproducibility. The population is
    then initialized so as to reproduce the calibrated stationary
    distributions while limiting finite-sample variability:

    - FAST and SLOW states match the observed initial occupancy;
    - state-conditional speed quantiles are stratified separately;
    - headings are stratified uniformly over the full circle;
    - latent speed and turning variables are initialized with covariance [R],
      thereby imposing the calibrated Gaussian-copula dependence from the
      first simulation step.

    Each selected grid coordinate yields one agent positioned at the centre
    of the corresponding cell. The returned agents therefore constitute an
    approximately isotropic population whose empirical marginals and latent
    dependence structure are already consistent with the calibrated model. *)
let initial_agents params grid =
  let rng = Rng.create params.seed in
  let coords =
    Initial_geometry.select grid (geometry_of_params params)
    |> Initial_geometry.random_subset rng ~n:params.agents
  in
  let n = Array.length coords in

  (* Initial motion states reproduce the observed FAST/SLOW occupancy while
     avoiding unnecessary binomial sampling noise. *)
  let motions =
    initial_motion_states rng n params.empirical.initial_fast_fraction
  in

  (* Each state-specific speed distribution is stratified separately.  This
     ensures that both empirical conditional marginals are evenly represented
     at t = 0, rather than letting a small initial sample omit their tails. *)
  let fast_count =
    Array.fold_left
      (fun acc state -> if state = FAST then acc + 1 else acc)
      0 motions
  in
  let slow_count = n - fast_count in
  let fast_u = stratified_uniforms rng fast_count in
  let slow_u = stratified_uniforms rng slow_count in
  let fast_index = ref 0 in
  let slow_index = ref 0 in

  (* Initial headings are uniformly stratified over the circle, then shuffled.
     This implements theta_i = 2 pi u_i and is consistent with isotropy. *)
  let headings =
    stratified_uniforms rng n
    |> Array.map (fun u -> 360.0 *. u)
  in

  (* A second stratified Gaussian rank is used to construct turn_z.  The
     speed-turn Gaussian-copula coefficient is imposed already at
     initialization, so the initial population starts with the documented
     contemporaneous dependence rather than acquiring it only later. *)
  let turn_noise_z =
    stratified_uniforms rng n
    |> Array.map Data.inverse_normal_cdf
  in

  Array.mapi
    (fun id coord ->
       let motion = motions.(id) in
       let u_speed =
         match motion with
         | FAST ->
             let u = fast_u.(!fast_index) in
             incr fast_index;
             u
         | SLOW ->
             let u = slow_u.(!slow_index) in
             incr slow_index;
             u
       in
       let speed_z = Data.inverse_normal_cdf u_speed in
       (* The initial latent pair is drawn from the stationary covariance R.
          In the exported model R_11 = R_22 = 1 and R_12 is the Gaussian-copula
          correlation between speed and |turn|.  Starting from R is essential:
          if Z_0 has covariance R, the exported VAR(1) keeps that covariance at
          every later time because R = A R A^T + Q. *)
       let rho0 =
         params.empirical.r12 /.
         sqrt (params.empirical.r11 *. params.empirical.r22)
       in
       let turn_z =
         correlated_standard_normals
           rho0
           (speed_z /. sqrt params.empirical.r11)
           turn_noise_z.(id)
         *. sqrt params.empirical.r22
       in
       let speed_um_s =
         Data.quantile
           (distribution_for_state params.empirical motion)
           u_speed
       in
       {
         id;
         x = float_of_int coord.Grid.col +. 0.5;
         y = float_of_int coord.Grid.row +. 0.5;
         age = 1;
         heading_deg = headings.(id);
         speed_um_s;
         speed_z;
         turn_z;
         motion;
       })
    coords



(* STOCHASTIC MODEL ********************************************************* *)



let transition_state rng empirical = function
  | FAST ->
      (* The FAST row of the empirical transition matrix is used directly. *)
      if Rng.chance rng empirical.Data.p_fast_fast then FAST else SLOW
  | SLOW ->
      (* The SLOW row of the empirical transition matrix is used directly. *)
      if Rng.chance rng empirical.Data.p_slow_slow then SLOW else FAST


let max_acceleration empirical multiplier =
  multiplier *. empirical.Data.absolute_acceleration_q90


(** Draw a two-dimensional Gaussian innovation vector with covariance
    matrix [Q] from the latent VAR(1) model.

    Two independent standard normal variates are transformed using a
    Cholesky factorization of the exported innovation covariance:

      Q = [[q11, q12],
           [q12, q22]].

    The returned pair represents the innovations applied to the latent
    speed and turning components, respectively. A dedicated branch
    handles the positive-semidefinite degenerate case where [q11] is
    effectively zero. *)
let gaussian_innovation_2d rng empirical =
  (* Draw epsilon_t ~ N(0,Q) using the Cholesky factor of the exact innovation
     covariance exported by Python:

       Q = [ q11 q12 ]
           [ q12 q22 ].

     For independent standard normals n1,n2:
       eps_v    = sqrt(q11) n1
       eps_turn = q12/sqrt(q11) n1
                  + sqrt(q22-q12^2/q11) n2.

     This is the point where q11, q12 and q22 are used directly. *)
  let n1 = standard_normal rng in
  let n2 = standard_normal rng in
  if empirical.Data.q11 > 1e-15 then begin
    let l11 = sqrt empirical.q11 in
    let l21 = empirical.q12 /. l11 in
    let residual = max 0.0 (empirical.q22 -. l21 *. l21) in
    let l22 = sqrt residual in
    l11 *. n1, l21 *. n1 +. l22 *. n2
  end else begin
    (* Positive semidefiniteness then requires q12 = 0.  This branch also
       supports a degenerate innovation in the speed component. *)
    0.0, sqrt (max 0.0 empirical.q22) *. n2
  end

let joint_latent_update rng empirical ag =
  (* Apply exactly the stationary bivariate Gaussian VAR(1) fitted in Python:

       [Z_v,t+1]   [a11 a12] [Z_v,t   ]   [epsilon_v,t   ]
       [Z_a,t+1] = [a21 a22] [Z_|turn|,t] + [epsilon_turn,t].

     The diagonal entries of A carry the principal temporal memories.
     The off-diagonal entries are equally important: a12 allows the previous
     turn magnitude to affect the next latent speed, while a21 allows the
     previous speed to affect the next latent turn magnitude.  Thus speed
     memory, turn memory and speed-turn coupling are represented jointly,
     rather than imposed as three potentially incompatible scalar AR(1)s. *)
  let eps_v, eps_turn = gaussian_innovation_2d rng empirical in
  let speed_z =
    empirical.Data.a11 *. ag.speed_z
    +. empirical.Data.a12 *. ag.turn_z
    +. eps_v
  in
  let turn_z =
    empirical.Data.a21 *. ag.speed_z
    +. empirical.Data.a22 *. ag.turn_z
    +. eps_turn
  in
  speed_z, turn_z

let update_speed params ag next_motion speed_z =
  let e = params.empirical in
  let target =
    Data.quantile
      (distribution_for_state e next_motion)
      (Data.normal_cdf speed_z)
  in

  (* Acceleration is not sampled independently.  It is derived from the speed
     update and bounded only by the documented numerical guard
       |a_t| <= ACCEL_CAP_MULTIPLIER * q90(|a|).
     q90(|a|) comes from the Python-generated scalar parameter CSV. *)
  let max_dv =
    max_acceleration e params.accel_cap_multiplier *. e.dt
  in
  let dv =
    Utils.clamp (-.max_dv) max_dv (target -. ag.speed_um_s)
  in
  max 0.0 (ag.speed_um_s +. dv)

let turn_sign rng empirical =
  let positive = max 0.0 empirical.Data.positive_turn_probability in
  let negative = max 0.0 empirical.Data.negative_turn_probability in
  let total = positive +. negative in
  if total <= 0.0 then
    if Rng.bool rng then 1.0 else -1.0
  else if Rng.float rng total < positive then
    1.0
  else
    -1.0

let update_turn rng empirical turn_z =
  (* turn_z is the second component of the jointly updated latent VAR(1).
     It is transformed through Phi and the full empirical inverse CDF of
     |Delta theta| exported in abca_empirical_quantiles.csv.  The sign is then
     sampled separately from the empirical left/right balance. *)
  let magnitude =
    Data.quantile empirical.Data.abs_turn (Data.normal_cdf turn_z)
  in
  turn_sign rng empirical *. magnitude



(* DISPLACEMENT FUNCTIONS *************************************************** *)

let move_agent params grid ag heading speed =
  let distance_cells = speed *. params.empirical.Data.dt /. params.microns_per_cell in
  let theta = heading *. Float.pi /. 180.0 in
  let x1 = ag.x +. distance_cells *. cos theta in
  let y1 = ag.y +. distance_cells *. sin theta in
  match params.topology with
  | Grid.Toroidal ->
      wrap_coordinate (Grid.cols grid) x1,
      wrap_coordinate (Grid.rows grid) y1,
      heading
  | Grid.Bounded ->
      if x1 >= 0.0 && x1 < float_of_int (Grid.cols grid)
         && y1 >= 0.0 && y1 < float_of_int (Grid.rows grid)
      then x1, y1, heading
      else
        let reflected =
          reflected_heading (Grid.rows grid) (Grid.cols grid) x1 y1 heading
        in
        let theta2 = reflected *. Float.pi /. 180.0 in
        let x2 = ag.x +. distance_cells *. cos theta2 in
        let y2 = ag.y +. distance_cells *. sin theta2 in
        Utils.clamp 0.0 (float_of_int (Grid.cols grid) -. 1e-9) x2,
        Utils.clamp 0.0 (float_of_int (Grid.rows grid) -. 1e-9) y2,
        reflected

let step_agent rng params grid ag =
  let next_motion = transition_state rng params.empirical ag.motion in

  (* One joint VAR(1) update uses the complete A and Q matrices exported by
     Python.  This simultaneously propagates temporal memory and cross-variable
     dependence in a mathematically coherent stationary process. *)
  let speed_z, turn_z =
    joint_latent_update rng params.empirical ag
  in
  let speed_um_s =
    update_speed params ag next_motion speed_z
  in
  let delta_heading =
    update_turn rng params.empirical turn_z
  in
  let proposed_heading =
    Utils.normalize_degrees (ag.heading_deg +. delta_heading)
  in
  let x, y, heading_deg = move_agent params grid ag proposed_heading speed_um_s in
  {
    ag with
    x;
    y;
    age = min params.max_age (ag.age + 1);
    heading_deg;
    speed_um_s;
    speed_z;
    turn_z;
    motion = next_motion;
  }

let step_agents rng params grid agents =
  (* Agents are physically continuous. Sharing a display cell is therefore
     not treated as a collision; no interaction law was measured. *)
  Array.map (step_agent rng params grid) agents



(* SIMULATION FUNCTIONS ***************************************************** *)

let empty_frame grid =
  Array.init (Grid.rows grid) (fun _ -> Array.make (Grid.cols grid) 0)

let frame_of_agents grid agents =
  let frame = empty_frame grid in
  Array.iter
    (fun ag ->
       let coord = coord_of_agent ag in
       if Grid.valid grid coord then
         frame.(coord.Grid.row).(coord.col) <- state_of_agent ag)
    agents;
  frame

let trace_record frame ag : Abca_io.Agent_trace.record =
  {
    frame;
    id = ag.id;
    x = ag.x;
    y = ag.y;
    row = row_of_agent ag;
    col = col_of_agent ag;
    angle = int_of_float (Float.round (Utils.normalize_degrees ag.heading_deg)) mod 360;
    age = ag.age;
    state = state_of_agent ag;
  }

let simulate params grid generations =
  let rng = Rng.create params.seed in
  let frames = Array.make (generations + 1) [||] in
  let trace = ref [] in
  let agents = ref (initial_agents params grid) in
  let record generation =
    Array.iter
      (fun ag -> trace := trace_record generation ag :: !trace)
      !agents
  in
  frames.(0) <- frame_of_agents grid !agents;
  record 0;
  for generation = 1 to generations do
    agents := step_agents rng params grid !agents;
    frames.(generation) <- frame_of_agents grid !agents;
    record generation
  done;
  frames, Array.of_list (List.rev !trace)

