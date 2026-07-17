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

module Utils = Zoospores_empirical_utils

type quantile_dist = {
  probs : float array;
  values : float array;
}

type empirical = {
  dt : float;
  initial_run_fraction : float;
  p_run_run : float;
  p_run_stop : float;
  p_stop_stop : float;
  p_stop_run : float;

  (* Parameters of the stationary latent bivariate Gaussian VAR(1)
       Z_(t+1) = A Z_t + epsilon_t, epsilon_t ~ N(0,Q).

     The Python extraction script estimates A and Q jointly from consecutive
     latent pairs (speed, |turn|), while R is the stationary covariance of Z_t.
     The OCaml plugin uses these exported values directly; it does not rebuild
     them from separate pairwise correlations. *)
  a11 : float;
  a12 : float;
  a21 : float;
  a22 : float;

  q11 : float;
  q12 : float;
  q22 : float;

  r11 : float;
  r12 : float;
  r22 : float;

  positive_turn_probability : float;
  negative_turn_probability : float;

  absolute_acceleration_q90 : float;
  default_accel_cap_multiplier : float;
  default_microns_per_cell : float;

  run_speed : quantile_dist;
  stop_speed : quantile_dist;
  abs_turn : quantile_dist;
}

let default_parameter_file =
  Filename.concat "plugins/zoospores" "abca_local_parameters.csv"

let default_quantile_basename = "abca_empirical_quantiles.csv"



(** Parse a single CSV record according to a minimal subset of the
    RFC 4180 specification.

    The parser supports quoted fields, embedded commas inside quoted
    fields, and escaped double quotes represented as [""]. It is
    intentionally lightweight, as the calibration files only require
    reading simple two-column parameter/value tables rather than
    providing a fully compliant CSV implementation. *)
let parse_csv_line line =
  let fields = ref [] in
  let buffer = Buffer.create 32 in
  let quoted = ref false in
  let i = ref 0 in
  let push () =
    fields := Buffer.contents buffer :: !fields;
    Buffer.clear buffer
  in
  while !i < String.length line do
    let c = line.[!i] in
    if !quoted then begin
      if c = '"' then begin
        if !i + 1 < String.length line && line.[!i + 1] = '"' then begin
          Buffer.add_char buffer '"';
          incr i
        end else
          quoted := false
      end else
        Buffer.add_char buffer c
    end else begin
      match c with
      | '"' -> quoted := true
      | ',' -> push ()
      | _ -> Buffer.add_char buffer c
    end;
    incr i
  done;
  push ();
  List.rev !fields

let read_parameter_table filename =
  let ic = open_in filename in
  Fun.protect
    ~finally:(fun () -> close_in_noerr ic)
    (fun () ->
       let table = Hashtbl.create 128 in
       let first = ref true in
       (try
          while true do
            let line = input_line ic in
            if !first then
              first := false
            else if String.trim line <> "" then
              match parse_csv_line line with
              | _section :: parameter :: value :: _unit :: _ ->
                  Hashtbl.replace table (String.trim parameter) (String.trim value)
              | _ ->
                  failwith ("Zoospore empirical: malformed CSV line: " ^ line)
          done
        with End_of_file -> ());
       table)

let finite_float s =
  let x = float_of_string s in
  match classify_float x with
  | FP_nan | FP_infinite -> None
  | FP_normal | FP_subnormal | FP_zero -> Some x

let required table key =
  match Hashtbl.find_opt table key with
  | None -> failwith ("Zoospore empirical: missing parameter " ^ key)
  | Some s ->
      (match finite_float s with
       | Some x -> x
       | None -> failwith ("Zoospore empirical: non-finite parameter " ^ key))

let optional table key default =
  match Hashtbl.find_opt table key with
  | None -> default
  | Some s -> (match finite_float s with Some x -> x | None -> default)

let dirname filename =
  let d = Filename.dirname filename in
  if d = "" then "." else d

let quantile_file_from_parameter_file parameter_file =
  Filename.concat (dirname parameter_file) default_quantile_basename

let read_quantile_table filename =
  let ic = open_in filename in
  Fun.protect
    ~finally:(fun () -> close_in_noerr ic)
    (fun () ->
       let table = Hashtbl.create 16 in
       let first = ref true in
       (try
          while true do
            let line = input_line ic in
            if !first then
              first := false
            else if String.trim line <> "" then
              match parse_csv_line line with
              | distribution :: condition :: probability :: value :: _unit :: _ ->
                  let key =
                    String.uppercase_ascii (String.trim distribution) ^ "|" ^
                    String.uppercase_ascii (String.trim condition)
                  in
                  let p =
                    match finite_float (String.trim probability) with
                    | Some x -> x
                    | None ->
                        failwith
                          ("Zoospore empirical: non-finite quantile probability in " ^
                           filename)
                  in
                  let v =
                    match finite_float (String.trim value) with
                    | Some x -> x
                    | None ->
                        failwith
                          ("Zoospore empirical: non-finite quantile value in " ^
                           filename)
                  in
                  let previous =
                    match Hashtbl.find_opt table key with
                    | Some xs -> xs
                    | None -> []
                  in
                  Hashtbl.replace table key ((p, v) :: previous)
              | _ ->
                  failwith
                    ("Zoospore empirical: malformed quantile CSV line: " ^ line)
          done
        with End_of_file -> ());
       table)

let required_quantile table ~distribution ~condition =
  let key =
    String.uppercase_ascii distribution ^ "|" ^
    String.uppercase_ascii condition
  in
  match Hashtbl.find_opt table key with
  | None ->
      failwith
        ("Zoospore empirical: missing empirical quantile distribution " ^ key)
  | Some pairs ->
      let pairs =
        List.sort (fun (p1, _) (p2, _) -> compare p1 p2) pairs
      in
      let probs = Array.of_list (List.map fst pairs) in
      let values = Array.of_list (List.map snd pairs) in
      if Array.length probs < 2 then
        failwith
          ("Zoospore empirical: quantile distribution " ^ key ^
           " contains fewer than two points");
      for i = 1 to Array.length probs - 1 do
        if probs.(i) < probs.(i - 1) then
          failwith
            ("Zoospore empirical: unsorted probabilities in " ^ key)
      done;
      { probs; values }

let load_empirical parameter_file quantile_file =
  let t = read_parameter_table parameter_file in
  let q = read_quantile_table quantile_file in
  {
    dt = required t "time_step";
    initial_run_fraction = required t "initial_run_fraction";
    p_run_run = required t "P_RUN_to_RUN";
    p_run_stop = required t "P_RUN_to_STOP";
    p_stop_stop = required t "P_STOP_to_STOP";
    p_stop_run = required t "P_STOP_to_RUN";

    (* Exact matrices exported by extract_abca_local_parameters_var1.py.
       A governs temporal memory and cross-lag effects; Q is the covariance of
       the Gaussian innovations; R is the stationary covariance used both for
       validation and for initialisation of the latent population. *)
    a11 = required t "latent_var_a11";
    a12 = required t "latent_var_a12";
    a21 = required t "latent_var_a21";
    a22 = required t "latent_var_a22";

    q11 = required t "latent_var_q11";
    q12 = required t "latent_var_q12";
    q22 = required t "latent_var_q22";

    r11 = required t "latent_var_r11";
    r12 = required t "latent_var_r12";
    r22 = required t "latent_var_r22";

    positive_turn_probability =
      optional t "positive_turn_probability" 0.5;
    negative_turn_probability =
      optional t "negative_turn_probability" 0.5;

    absolute_acceleration_q90 =
      required t "absolute_acceleration_q90";
    default_accel_cap_multiplier =
      optional t "accel_cap_multiplier" 3.0;
    default_microns_per_cell =
      optional t "microns_per_cell" 10.0;

    run_speed =
      required_quantile q ~distribution:"speed" ~condition:"RUN";
    stop_speed =
      required_quantile q ~distribution:"speed" ~condition:"STOP";
    abs_turn =
      required_quantile q ~distribution:"turn_angle_absolute" ~condition:"ALL";
  }

let interpolate x0 y0 x1 y1 x =
  if x1 = x0 then y0
  else y0 +. (x -. x0) *. (y1 -. y0) /. (x1 -. x0)

let quantile dist u =
  let u = Utils.clamp01 u in
  let n = Array.length dist.probs in
  let rec find i =
    if i >= n - 1 then dist.values.(n - 1)
    else if u <= dist.probs.(i + 1) then
      interpolate
        dist.probs.(i) dist.values.(i)
        dist.probs.(i + 1) dist.values.(i + 1)
        u
    else find (i + 1)
  in
  find 0



(** Approximate the cumulative distribution function (CDF) of the
    standard normal distribution.

    This implementation computes the CDF via the error function:

      Φ(x) = 0.5 * (1 + erf(x / sqrt(2)))

    where [erf] is evaluated using the classical five-term rational
    approximation of Abramowitz and Stegun (1964, Handbook of
    Mathematical Functions, formula 7.1.26). The coefficients below
    are the published constants of this approximation and provide
    good accuracy while avoiding any external numerical dependency. *)
let normal_cdf x =
  let sign = if x < 0.0 then -1.0 else 1.0 in
  let z = abs_float x /. sqrt 2.0 in
  let t = 1.0 /. (1.0 +. 0.3275911 *. z) in
  let a1 = 0.254829592
  and a2 = -0.284496736
  and a3 = 1.421413741
  and a4 = -1.453152027
  and a5 = 1.061405429 in
  let erf =
    sign *. (1.0 -.
      (((((a5 *. t +. a4) *. t +. a3) *. t +. a2) *. t +. a1) *. t)
      *. exp (-. z *. z))
  in
  0.5 *. (1.0 +. erf)



(** Approximate the inverse cumulative distribution function (quantile
    function) of the standard normal distribution.

    Given a probability [p] in [0,1], this function returns the value
    [x] such that [Φ(x) = p], where [Φ] denotes the standard normal CDF.

    The implementation follows Peter J. Acklam's widely used rational
    approximation, using separate polynomial approximations for the
    lower tail, upper tail, and central region. The coefficients below
    are those published by Acklam and provide high numerical accuracy
    over the entire probability range.

    Input probabilities are clamped to [[1e-12, 1 - 1e-12]] to avoid
    singularities at the boundaries.

    Reference:
    Peter J. Acklam, "An algorithm for computing the inverse normal
    cumulative distribution function", 2003.
    https://stackedboxes.org/2017/05/01/acklams-normal-quantile-function/ *)
let inverse_normal_cdf p =
  let p = Utils.clamp 1e-12 (1.0 -. 1e-12) p in
  let a = [|
    -3.969683028665376e+01; 2.209460984245205e+02;
    -2.759285104469687e+02; 1.383577518672690e+02;
    -3.066479806614716e+01; 2.506628277459239e+00
  |] in
  let b = [|
    -5.447609879822406e+01; 1.615858368580409e+02;
    -1.556989798598866e+02; 6.680131188771972e+01;
    -1.328068155288572e+01
  |] in
  let c = [|
    -7.784894002430293e-03; -3.223964580411365e-01;
    -2.400758277161838e+00; -2.549732539343734e+00;
    4.374664141464968e+00; 2.938163982698783e+00
  |] in
  let d = [|
    7.784695709041462e-03; 3.224671290700398e-01;
    2.445134137142996e+00; 3.754408661907416e+00
  |] in
  let plow = 0.02425 in
  let phigh = 1.0 -. plow in
  if p < plow then begin
    let q = sqrt (-2.0 *. log p) in
    (((((c.(0) *. q +. c.(1)) *. q +. c.(2)) *. q +. c.(3)) *. q +. c.(4)) *. q +. c.(5)) /.
    ((((d.(0) *. q +. d.(1)) *. q +. d.(2)) *. q +. d.(3)) *. q +. 1.0)
  end else if p > phigh then begin
    let q = sqrt (-2.0 *. log (1.0 -. p)) in
    -.(((((c.(0) *. q +. c.(1)) *. q +. c.(2)) *. q +. c.(3)) *. q +. c.(4)) *. q +. c.(5)) /.
    ((((d.(0) *. q +. d.(1)) *. q +. d.(2)) *. q +. d.(3)) *. q +. 1.0)
  end else begin
    let q = p -. 0.5 in
    let r = q *. q in
    (((((a.(0) *. r +. a.(1)) *. r +. a.(2)) *. r +. a.(3)) *. r +. a.(4)) *. r +. a.(5)) *. q /.
    (((((b.(0) *. r +. b.(1)) *. r +. b.(2)) *. r +. b.(3)) *. r +. b.(4)) *. r +. 1.0)
  end



let validate_latent_var1 empirical =
  let tolerance = 1e-7 in

  (* Validate R as a positive-definite covariance matrix. *)
  if empirical.r11 <= 0.0 || empirical.r22 <= 0.0 then
    invalid_arg
      "Zoospore empirical: latent stationary variances R11 and R22 must be positive";
  let det_r =
    empirical.r11 *. empirical.r22 -. empirical.r12 *. empirical.r12
  in
  if det_r <= 0.0 then
    invalid_arg
      "Zoospore empirical: stationary latent covariance R must be positive definite";

  (* Validate Q as positive semidefinite. *)
  if empirical.q11 < -.tolerance || empirical.q22 < -.tolerance then
    invalid_arg
      "Zoospore empirical: innovation covariance Q has a negative diagonal";
  let det_q =
    empirical.q11 *. empirical.q22 -. empirical.q12 *. empirical.q12
  in
  if det_q < -.tolerance then
    invalid_arg
      "Zoospore empirical: innovation covariance Q is not positive semidefinite";

  (* Check the defining stationarity identity R = A R A^T + Q. *)
  let ar11 =
    empirical.a11 *. empirical.r11 +. empirical.a12 *. empirical.r12
  in
  let ar12 =
    empirical.a11 *. empirical.r12 +. empirical.a12 *. empirical.r22
  in
  let ar21 =
    empirical.a21 *. empirical.r11 +. empirical.a22 *. empirical.r12
  in
  let ar22 =
    empirical.a21 *. empirical.r12 +. empirical.a22 *. empirical.r22
  in
  let predicted_r11 =
    ar11 *. empirical.a11 +. ar12 *. empirical.a12 +. empirical.q11
  in
  let predicted_r12 =
    ar11 *. empirical.a21 +. ar12 *. empirical.a22 +. empirical.q12
  in
  let predicted_r22 =
    ar21 *. empirical.a21 +. ar22 *. empirical.a22 +. empirical.q22
  in
  if abs_float (predicted_r11 -. empirical.r11) > 1e-5
     || abs_float (predicted_r12 -. empirical.r12) > 1e-5
     || abs_float (predicted_r22 -. empirical.r22) > 1e-5
  then
    invalid_arg
      "Zoospore empirical: exported A, Q and R do not satisfy R = A R A^T + Q";

  (* For a 2x2 matrix, both eigenvalues must lie inside the unit disk. *)
  let trace = empirical.a11 +. empirical.a22 in
  let determinant =
    empirical.a11 *. empirical.a22 -. empirical.a12 *. empirical.a21
  in
  let discriminant = trace *. trace -. 4.0 *. determinant in
  let spectral_radius =
    if discriminant >= 0.0 then begin
      let root = sqrt discriminant in
      max
        (abs_float ((trace +. root) /. 2.0))
        (abs_float ((trace -. root) /. 2.0))
    end else
      sqrt (abs_float determinant)
  in
  if spectral_radius >= 1.0 -. tolerance then
    invalid_arg
      "Zoospore empirical: latent VAR(1) transition matrix A is not stationary"


