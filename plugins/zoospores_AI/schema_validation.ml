(*
   Model-local schema validation for the reconciled zoospore AI portfolio.

   Important design choice:
   ------------------------
   The parameter TOML contains sections for all canonical models, but an ABCA
   invocation executes only one registered model. Therefore validation is
   intentionally restricted to:

     1. [common]
     2. [model.<selected model>]

   Sections belonging to other canonical models are ignored for that run.

   Variant-dependent sections are validated conditionally. In particular,
   CAN-HET-SPEED requires different keys for the RUN2 and RUN3 formulations.
   CAN-SPEED-TURN also checks that its declared formula is one of the two
   reconciled alternatives, although both alternatives use the same key set.

   Numerical domains and enum semantics are checked later by the main plugin
   when values are parsed. This module validates section/key structure and the
   variant-dependent presence of required parameters.
*)

let schema_section tbl name =
  match List.assoc_opt name tbl with
  | Some sec -> sec
  | None ->
      failwith
        ("missing required parameter section [" ^ name ^ "]")

let schema_value sec section_name key =
  match List.assoc_opt key sec with
  | Some v -> v
  | None ->
      failwith
        ("missing required parameter '" ^ section_name ^ "." ^ key ^ "'")

let check_exact_keys ~section_name ~required ~allowed sec =
  List.iter
    (fun key ->
      if not (List.mem_assoc key sec) then
        failwith
          ("missing required parameter '"
          ^ section_name ^ "." ^ key ^ "'"))
    required;

  List.iter
    (fun (key, _) ->
      if not (List.mem key allowed) then
        failwith
          ("unknown parameter '"
          ^ section_name ^ "." ^ key ^ "'"))
    sec

let check_formula ~section_name sec allowed =
  let formula = schema_value sec section_name "formula" in
  if not (List.mem formula allowed) then
    failwith
      ("parameter '"
      ^ section_name
      ^ ".formula' must be one of: "
      ^ String.concat ", " allowed);
  formula

let common_required =
  [
    "dt_sec";
    "agents";
    "initial_position";
    "initial_heading";
    "boundary";
    "record_initial_frame";
  ]

let validate_common tbl =
  let section_name = "common" in
  let sec = schema_section tbl section_name in
  check_exact_keys
    ~section_name
    ~required:common_required
    ~allowed:common_required
    sec

let model_keys model_name sec =
  match model_name with
  | "CAN-IID" ->
      [ "step_mean_um"; "step_sd_um" ]

  | "CAN-BALLISTIC" ->
      [ "step_mean_um"; "step_sd_um" ]

  | "CAN-PCRW" ->
      [
        "step_mean_um";
        "step_sd_um";
        "turn_sd_rad";
        "innovation_law";
      ]

  | "CAN-TURN-AR1" ->
      [
        "step_mean_um";
        "step_sd_um";
        "turn_sd_rad";
        "turn_memory";
        "initial_turn";
      ]

  | "CAN-VELOCITY-OU" ->
      [
        "velocity_rho";
        "velocity_noise_um";
        "initial_velocity";
      ]

  | "CAN-SPEED-TURN" ->
      ignore
        (check_formula
           ~section_name:"model.CAN-SPEED-TURN"
           sec
           [ "RUN2_additive_rad"; "RUN3_multiplicative" ]);
      [
        "formula";
        "step_mean_um";
        "step_sd_um";
        "turn_sd_rad";
        "coupling";
        "turn_scale_floor";
      ]

  | "CAN-SWITCH-PAUSE" ->
      [
        "p_move_stay";
        "p_pause_stay";
        "step_mean_um";
        "step_sd_um";
        "turn_sd_rad";
        "pause_emission";
      ]

  | "CAN-SWITCH-TURN" ->
      [
        "switch_prob";
        "run_turn_sd_rad";
        "reorient_turn_sd_rad";
        "step_mean_um";
        "step_sd_um";
        "transition_form";
      ]

  | "CAN-SWITCH-SPEED" ->
      [
        "switch_prob";
        "slow_factor";
        "step_min_um";
        "step_mean_um";
        "step_sd_um";
        "turn_sd_rad";
        "transition_form";
      ]

  | "CAN-HET-SPEED" ->
      let formula =
        check_formula
          ~section_name:"model.CAN-HET-SPEED"
          sec
          [ "RUN2_additive_fixed"; "RUN3_multiplicative" ]
      in
      if formula = "RUN2_additive_fixed" then
        [
          "formula";
          "step_mean_um";
          "turn_sd_rad";
          "hetero_sd_um";
        ]
      else
        [
          "formula";
          "step_mean_um";
          "step_sd_um";
          "turn_sd_rad";
          "hetero_cv";
          "hetero_multiplier_min";
          "step_min_um";
        ]

  | "CAN-REVERSAL" ->
      [
        "step_mean_um";
        "step_sd_um";
        "turn_sd_rad";
        "reversal_prob";
        "reversal_angle_rad";
      ]

  | "CAN-EMP-LOCAL" ->
      [
        "training_transition_table_uri";
        "training_transition_table_sha256";
        "conditioning";
      ]

  | "CAN-EMP-WHOLE" ->
      [
        "training_trajectory_library_uri";
        "training_trajectory_library_sha256";
        "orientation_policy";
        "post_sequence_policy";
      ]

  | x ->
      failwith ("schema validation: unknown canonical model " ^ x)

let validate_model_section tbl model_name =
  let section_name = "model." ^ model_name in
  let sec = schema_section tbl section_name in
  let keys = model_keys model_name sec in
  check_exact_keys
    ~section_name
    ~required:keys
    ~allowed:keys
    sec

let validate_schema_for_model tbl model_name =
  validate_common tbl;
  validate_model_section tbl model_name
