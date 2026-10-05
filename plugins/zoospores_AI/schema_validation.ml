(*
   Schema validation for the reconciled canonical zoospore-model portfolio.

   This module defines the exact set of parameter-file sections and keys that
   are accepted by the canonical ABCA plugin.

   Validation is intentionally strict:
   - unknown sections are rejected;
   - unknown keys are rejected;
   - every required section must be present;
   - every required key must be present.

   Type, range, domain, and enum validation are handled later by the main
   plugin when values are parsed for a specific canonical model. This module
   therefore validates the *shape* of the TOML parameter file rather than the
   numerical meaning of each value.

   The module is included from the main plugin with:

       include Schema_validation

   so [schema] and [validate_schema] become directly available in the plugin.
*)


(* -------------------------------------------------------------------------- *)
(* Accepted parameter-file schema                                             *)
(* -------------------------------------------------------------------------- *)

(*
   Each entry associates one TOML section with the complete set of keys that
   section must contain.

   The schema mirrors the external parameter contract shared by the fitting
   pipeline and the executable canonical-model plugin.
*)
let schema =
  [
    ( "common",
      [
        "dt_sec";
        "agents";
        "initial_position";
        "initial_heading";
        "boundary";
        "record_initial_frame";
      ] );

    ( "model.CAN-IID",
      [
        "step_mean_um";
        "step_sd_um";
      ] );

    ( "model.CAN-BALLISTIC",
      [
        "step_mean_um";
        "step_sd_um";
      ] );

    ( "model.CAN-PCRW",
      [
        "step_mean_um";
        "step_sd_um";
        "turn_sd_rad";
        "innovation_law";
      ] );

    ( "model.CAN-TURN-AR1",
      [
        "step_mean_um";
        "step_sd_um";
        "turn_sd_rad";
        "turn_memory";
        "initial_turn";
      ] );

    ( "model.CAN-VELOCITY-OU",
      [
        "velocity_rho";
        "velocity_noise_um";
        "initial_velocity";
      ] );

    ( "model.CAN-SPEED-TURN",
      [
        "formula";
        "step_mean_um";
        "step_sd_um";
        "turn_sd_rad";
        "coupling";
        "turn_scale_floor";
      ] );

    ( "model.CAN-SWITCH-PAUSE",
      [
        "p_move_stay";
        "p_pause_stay";
        "step_mean_um";
        "step_sd_um";
        "turn_sd_rad";
        "pause_emission";
      ] );

    ( "model.CAN-SWITCH-TURN",
      [
        "switch_prob";
        "run_turn_sd_rad";
        "reorient_turn_sd_rad";
        "step_mean_um";
        "step_sd_um";
        "transition_form";
      ] );

    ( "model.CAN-SWITCH-SPEED",
      [
        "switch_prob";
        "slow_factor";
        "step_min_um";
        "step_mean_um";
        "step_sd_um";
        "turn_sd_rad";
        "transition_form";
      ] );

    ( "model.CAN-HET-SPEED",
      [
        "formula";
        "step_mean_um";
        "step_sd_um";
        "turn_sd_rad";
        "hetero_sd_um";
        "hetero_cv";
        "hetero_multiplier_min";
        "step_min_um";
      ] );

    ( "model.CAN-REVERSAL",
      [
        "step_mean_um";
        "step_sd_um";
        "turn_sd_rad";
        "reversal_prob";
        "reversal_angle_rad";
      ] );

    ( "model.CAN-EMP-LOCAL",
      [
        "training_transition_table_uri";
        "training_transition_table_sha256";
        "conditioning";
      ] );

    ( "model.CAN-EMP-WHOLE",
      [
        "training_trajectory_library_uri";
        "training_trajectory_library_sha256";
        "orientation_policy";
        "post_sequence_policy";
      ] );
  ]


(* -------------------------------------------------------------------------- *)
(* Structural schema validation                                               *)
(* -------------------------------------------------------------------------- *)

(*
   Validate a parsed TOML table against [schema].

   The input [tbl] has the representation used by the main plugin:

       (section_name * (key * raw_value) list) list

   Validation proceeds in two passes:

   1. Reject anything not explicitly declared by the schema.
      This prevents unnoticed spelling mistakes, obsolete parameters, or
      accidental carry-over from exploratory model implementations.

   2. Require every declared section and every declared key.
      This prevents silent use of unspecified defaults.

   Duplicate sections and duplicate keys are already rejected by the TOML
   parser before this function is called.
*)
let validate_schema tbl =
  let allowed_sections =
    List.map fst schema
  in

  (* Pass 1: reject unknown sections and unknown keys. *)
  List.iter
    (fun (name, entries) ->
      if not (List.mem name allowed_sections) then
        failwith
          ("parameter file: unknown section [" ^ name ^ "]");

      let allowed_keys =
        List.assoc name schema
      in

      List.iter
        (fun (key, _) ->
          if not (List.mem key allowed_keys) then
            failwith
              ("parameter file: unknown key "
              ^ name
              ^ "."
              ^ key))
        entries)
    tbl;

  (* Pass 2: require every section and every key declared by the schema. *)
  List.iter
    (fun (name, required_keys) ->
      let entries =
        match List.assoc_opt name tbl with
        | Some entries ->
            entries
        | None ->
            failwith
              ("missing required parameter section ["
              ^ name
              ^ "]")
      in

      List.iter
        (fun key ->
          if not (List.mem_assoc key entries) then
            failwith
              ("missing required parameter '"
              ^ name
              ^ "."
              ^ key
              ^ "'"))
        required_keys)
    schema
