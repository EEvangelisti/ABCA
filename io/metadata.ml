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

type t = (string * string) list

let empty =
  []

let add key value metadata =
  (key, value) :: List.remove_assoc key metadata

let get key metadata =
  List.assoc_opt key metadata

let of_list xs =
  List.fold_left
    (fun acc (key, value) ->
       add key value acc)
    empty
    xs

let to_list metadata =
  List.rev metadata

let to_json metadata =
  let escape s =
    String.escaped s
  in

  metadata
  |> List.rev
  |> List.map (fun (k, v) ->
      Printf.sprintf
        "  \"%s\": \"%s\""
        (escape k)
        (escape v))
  |> String.concat ",\n"
  |> Printf.sprintf "{\n%s\n}"

let of_json json =
  [ "raw_json", json ]
