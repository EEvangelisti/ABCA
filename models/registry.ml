(* registry.ml *)

open Model

exception Unknown_model of string

let registry : (string, Model.t) Hashtbl.t =
  Hashtbl.create 32

let register model =
  Hashtbl.replace registry model.name model

let exists name =
  Hashtbl.mem registry name

let find name =
  match Hashtbl.find_opt registry name with
  | Some model ->
      model
  | None ->
      raise (Unknown_model name)

let all () =
  registry
  |> Hashtbl.to_seq_values
  |> List.of_seq
  |> List.sort (fun a b ->
      match String.compare
              (Model.family_to_string a.Model.family)
              (Model.family_to_string b.Model.family)
      with
      | 0 -> String.compare a.Model.name b.Model.name
      | n -> n)

let names () =
  all ()
  |> List.map (fun m -> m.name)

let by_family family =
  all ()
  |> List.filter (fun m ->
      m.family = family)

let families () =
  all ()
  |> List.map (fun m -> m.family)
  |> List.sort_uniq compare
