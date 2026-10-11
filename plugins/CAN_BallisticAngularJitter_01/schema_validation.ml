(*
   Parameter schema for Ballistic_angular_jitter_c3 only.

   Validate the exact keys of [common] and
   [model.C3-CAN-BALLISTIC-ANGULAR-JITTER-01].
   Unrelated sections in a legacy portfolio TOML are ignored.
   Numerical domains and enum values are checked by the model plugin.

   The original validate_schema_for_model interface is retained for
   compatibility with existing callers.
*)

let c3_model_name = "C3-CAN-BALLISTIC-ANGULAR-JITTER-01"

let schema_section tbl name =
  match List.assoc_opt name tbl with
  | Some sec -> sec
  | None -> failwith ("missing required parameter section [" ^ name ^ "]")

let check_exact_keys ~section_name ~required sec =
  List.iter
    (fun key ->
      if not (List.mem_assoc key sec) then
        failwith
          ("missing required parameter '" ^ section_name ^ "." ^ key ^ "'"))
    required;
  List.iter
    (fun (key, _) ->
      if not (List.mem key required) then
        failwith
          ("unknown parameter '" ^ section_name ^ "." ^ key ^ "'"))
    sec

let common_keys =
  [
    "dt_sec";
    "agents";
    "initial_position";
    "initial_heading";
    "boundary";
    "record_initial_frame";
  ]

let c3_keys =
  [ "step_mean_um"; "step_sd_um"; "sigma_theta_rad_per_step" ]

let validate_common tbl =
  let section_name = "common" in
  let sec = schema_section tbl section_name in
  check_exact_keys ~section_name ~required:common_keys sec

let validate_model_section tbl model_name =
  if model_name <> c3_model_name then
    failwith ("schema validation: unknown canonical model " ^ model_name);
  let section_name = "model." ^ model_name in
  let sec = schema_section tbl section_name in
  check_exact_keys ~section_name ~required:c3_keys sec

let validate_schema_for_model tbl model_name =
  validate_common tbl;
  validate_model_section tbl model_name
