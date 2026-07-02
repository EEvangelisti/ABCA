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

open Printf

module type STATE_CODEC = sig
  type t

  val to_string : t -> string
end

let xml_escape s =
  let open Buffer in
  let b = create (String.length s) in
  String.iter
    (function
      | '&'  -> add_string b "&amp;"
      | '<'  -> add_string b "&lt;"
      | '>'  -> add_string b "&gt;"
      | '"'  -> add_string b "&quot;"
      | '\'' -> add_string b "&apos;"
      | c    -> add_char b c)
    s;
  contents b



let check_frame_shape ~rows ~cols frame =
  (Array.length frame = rows 
    || invalid_arg "Io_xml: invalid frame row count")
    |> ignore;

  Array.iter
    (fun row ->
      (Array.length row = cols 
        || invalid_arg "Io_xml: invalid frame column count")
        |> ignore)
  frame



let save_frames
    (type state)
    ~filename
    ~model
    ~grid
    ~generation
    ~(frames : state array array array)
    ~(codec : (module STATE_CODEC with type t = state)) =

  let module Codec =
    (val codec : STATE_CODEC with type t = state)
  in

  let rows = Abca.Grid.rows grid in
  let cols = Abca.Grid.cols grid in

  Array.iter
    (check_frame_shape ~rows ~cols)
    frames;

  let oc = open_out filename in

  Fun.protect
    ~finally:(fun () -> close_out_noerr oc)
    (fun () ->
       fprintf oc "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";

       fprintf oc
         "<automates model=\"%s\" rows=\"%d\" cols=\"%d\" generation=\"%d\" frames=\"%d\">\n"
         (xml_escape model)
         rows
         cols
         generation
         (Array.length frames);

       Array.iteri
         (fun frame_index frame ->
            fprintf oc "  <frame index=\"%d\">\n" frame_index;

            Array.iteri
              (fun row cells ->
                 Array.iteri
                   (fun col state ->
                      let s = Codec.to_string state in

                      if s <> "0" && s <> "." && s <> "" then
                        fprintf oc
                          "    <cell row=\"%d\" col=\"%d\" state=\"%s\" />\n"
                          row
                          col
                          (xml_escape s))
                   cells)
              frame;

            fprintf oc "  </frame>\n")
         frames;

       fprintf oc "</automates>\n")
 
 
let save_agent_trace_trackmate ~filename (agents : Agent_trace.t) =
  let by_id =
    let table = Hashtbl.create 257 in
    Array.iter
      (fun r ->
         let id = r.Agent_trace.id in
         let previous =
           match Hashtbl.find_opt table id with
           | None -> []
           | Some xs -> xs
         in
         Hashtbl.replace table id (r :: previous))
      agents;
    table
  in

  let ids =
    Hashtbl.fold (fun id _ acc -> id :: acc) by_id []
    |> List.sort compare
  in

  let oc = open_out filename in
  Fun.protect
    ~finally:(fun () -> close_out_noerr oc)
    (fun () ->
       output_string oc "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
       output_string oc "<root>\n";

       List.iter
         (fun id ->
            let trajectory =
              Hashtbl.find by_id id
              |> List.sort
                   (fun a b ->
                      compare a.Agent_trace.frame b.Agent_trace.frame)
            in

            output_string oc "  <particle>\n";

            List.iter
              (fun r ->
                fprintf oc
                  "    <detection t=\"%d\" x=\"%.6f\" y=\"%.6f\" />\n"
                  r.Agent_trace.frame
                  r.x
                  r.y)
              trajectory;

            output_string oc "  </particle>\n")
         ids;

       output_string oc "</root>\n")
 

