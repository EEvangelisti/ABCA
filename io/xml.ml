(*
 * ABCA (Agent-Based Cellular Automata)
 * XML export utilities.
 *
 * The trajectory exporter below deliberately writes the simple XML format
 * consumed by extract_zoospore_metrics.py:
 *
 *   <root>
 *     <particle id="...">
 *       <detection t="..." x="..." y="..." />
 *     </particle>
 *   </root>
 *)

open Printf

module type STATE_CODEC = sig
  type t
  val to_string : t -> string
end

let xml_escape s =
  let b = Buffer.create (String.length s) in
  String.iter
    (function
      | '&'  -> Buffer.add_string b "&amp;"
      | '<'  -> Buffer.add_string b "&lt;"
      | '>'  -> Buffer.add_string b "&gt;"
      | '"'  -> Buffer.add_string b "&quot;"
      | '\'' -> Buffer.add_string b "&apos;"
      | c    -> Buffer.add_char b c)
    s;
  Buffer.contents b

let check_frame_shape ~rows ~cols frame =
  if Array.length frame <> rows then
    invalid_arg "Xml.save_frames: invalid frame row count";
  Array.iter
    (fun row ->
       if Array.length row <> cols then
         invalid_arg "Xml.save_frames: invalid frame column count")
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
  Array.iter (check_frame_shape ~rows ~cols) frames;

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
                      let value = Codec.to_string state in
                      if value <> "0" && value <> "." && value <> "" then
                        fprintf oc
                          "    <cell row=\"%d\" col=\"%d\" state=\"%s\" />\n"
                          row
                          col
                          (xml_escape value))
                   cells)
              frame;
            output_string oc "  </frame>\n")
         frames;

       output_string oc "</automates>\n")

(* Return records ordered by frame, retaining only the first record for each
   frame. extract_zoospore_metrics.py performs the same de-duplication. *)
let sort_and_deduplicate_trajectory records =
  let sorted =
    List.sort
      (fun a b -> compare a.Agent_trace.frame b.Agent_trace.frame)
      records
  in
  let rec loop previous_frame acc = function
    | [] -> List.rev acc
    | record :: rest ->
        let frame = record.Agent_trace.frame in
        if Some frame = previous_frame then
          loop previous_frame acc rest
        else
          loop (Some frame) (record :: acc) rest
  in
  loop None [] sorted

(*
 * Despite its historical name, this function intentionally exports the
 * "simple particle XML" format expected by extract_zoospore_metrics.py.
 *
 * Required structure:
 *   root
 *     particle
 *       detection with attributes t, x and y
 *)
let save_agent_trace_trackmate ~filename (agents : Agent_trace.t) =
  let trajectories = Hashtbl.create 257 in

  Array.iter
    (fun record ->
       let agent_id = record.Agent_trace.id in
       let previous =
         match Hashtbl.find_opt trajectories agent_id with
         | Some records -> records
         | None -> []
       in
       Hashtbl.replace trajectories agent_id (record :: previous))
    agents;

  let agent_ids =
    Hashtbl.fold (fun agent_id _ acc -> agent_id :: acc) trajectories []
    |> List.sort compare
  in

  let oc = open_out filename in
  Fun.protect
    ~finally:(fun () -> close_out_noerr oc)
    (fun () ->
       output_string oc "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
       output_string oc "<root>\n";

       List.iter
         (fun agent_id ->
            let records =
              Hashtbl.find trajectories agent_id
              |> sort_and_deduplicate_trajectory
            in

            (* The Python reader ignores the optional id attribute, but it is
               useful for inspecting files manually. *)
            fprintf oc "  <particle id=\"%d\">\n" agent_id;

            List.iter
              (fun record ->
                 fprintf oc
                   "    <detection t=\"%d\" x=\"%.17g\" y=\"%.17g\" />\n"
                   record.Agent_trace.frame
                   record.Agent_trace.x
                   record.Agent_trace.y)
              records;

            output_string oc "  </particle>\n")
         agent_ids;

       output_string oc "</root>\n")
