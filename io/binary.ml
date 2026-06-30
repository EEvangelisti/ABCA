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

module type STATE_CODEC = sig
  type t

  val to_int32 : t -> int32
  val of_int32 : int32 -> t
end

type header = {
  version    : int;
  rows       : int;
  cols       : int;
  generation : int;
  frames     : int;
  metadata   : Metadata.t;
}

type 'state archive = {
  header : header;
  frames : 'state array array array;
  agents : Agent_trace.t;
}

let magic = "AUTOMATES"
let version = 3

let make_archive
    ~rows
    ~cols
    ~generation
    ~metadata
    ~frames
    ?(agents = Agent_trace.empty)
    () =
  {
    header = {
      version;
      rows;
      cols;
      generation;
      frames = Array.length frames;
      metadata;
    };
    frames;
    agents;
  }

let write_string_fixed oc s =
  output_string oc s

let read_string_fixed ic n =
  really_input_string ic n

let write_int32 oc x =
  output_binary_int oc (Int32.to_int x)

let read_int32 ic =
  Int32.of_int (input_binary_int ic)

let write_int oc x =
  output_binary_int oc x

let read_int ic =
  input_binary_int ic

let check_frame_shape ~rows ~cols frame =
  if Array.length frame <> rows then
    invalid_arg "Io_binary: invalid frame row count";

  Array.iter
    (fun row ->
       if Array.length row <> cols then
         invalid_arg "Io_binary: invalid frame column count")
    frame



let save
    (type state)
    ~filename
    ~(archive : state archive)
    ~(codec : (module STATE_CODEC with type t = state)) =

  let module Codec =
    (val codec : STATE_CODEC with type t = state)
  in

  let header = archive.header in
  let rows = header.rows in
  let cols = header.cols in
  let frames = archive.frames in
  let agents = archive.agents in

  if header.frames <> Array.length frames then
    invalid_arg "Binary.save: header.frames does not match frame array length";

  Array.iter
    (check_frame_shape ~rows ~cols)
    frames;

  let oc = open_out_bin filename in

  Fun.protect
    ~finally:(fun () -> close_out_noerr oc)
    (fun () ->
       write_string_fixed oc magic;
       write_int oc header.version;
       write_int oc rows;
       write_int oc cols;
       write_int oc header.generation;
       write_int oc (Array.length frames);
      
       let metadata_json = Metadata.to_json header.metadata in
       write_int oc (String.length metadata_json);
       output_string oc metadata_json;

       Array.iter
         (fun frame ->
            Array.iter
              (fun row ->
                 Array.iter
                   (fun state ->
                      write_int32 oc (Codec.to_int32 state))
                   row)
              frame)
         frames;

         write_int oc (Array.length agents);

         Array.iter
           (fun r ->
              write_int oc r.Agent_trace.frame;
              write_int oc r.id;
              write_int oc r.row;
              write_int oc r.col;
              write_int oc r.angle;
              write_int oc r.age;
              write_int oc r.state)
           agents
    )





let load_frames
    (type state)
    ~filename
    ~(codec : (module STATE_CODEC with type t = state)) =

  let module Codec =
    (val codec : STATE_CODEC with type t = state)
  in

  let ic = open_in_bin filename in

  Fun.protect
    ~finally:(fun () -> close_in_noerr ic)
    (fun () ->
       let found_magic = read_string_fixed ic (String.length magic) in

       if found_magic <> magic then
         failwith "Io_binary.load_frames: invalid file format";

       let file_version = read_int ic in

       if file_version <> version then
         failwith "Io_binary.load_frames: unsupported file version";

       let rows = read_int ic in
       let cols = read_int ic in
       let generation = read_int ic in
       let frame_count = read_int ic in

       let metadata_len = read_int ic in
       let metadata_json = really_input_string ic metadata_len in
       let metadata = Metadata.of_json metadata_json in

       if rows <= 0 || cols <= 0 || frame_count < 0 then
         failwith "Io_binary.load_frames: corrupted header";

       let frames =
         Array.init frame_count (fun _ ->
             Array.init rows (fun _ ->
                 Array.init cols (fun _ ->
                     Codec.of_int32 (read_int32 ic))))
       in

       let agents =
         let n =
           try read_int ic
           with End_of_file -> 0
         in

         Array.init n (fun _ ->
             {
               Agent_trace.frame = read_int ic;
               id = read_int ic;
               row = read_int ic;
               col = read_int ic;
               angle = read_int ic;
               age = read_int ic;
               state = read_int ic;
             })
       in

       let header = {
         version = file_version;
         rows;
         cols;
         generation;
         frames = frame_count;
         metadata
       } in

       header, frames, agents)


let load
    (type state)
    ~filename
    ~(codec : (module STATE_CODEC with type t = state)) =

  let header, frames, agents =
    load_frames ~filename ~codec
  in

  {
    header;
    frames;
    agents;
  }
