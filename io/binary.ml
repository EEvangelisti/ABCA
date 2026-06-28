(* io_binary.ml *)

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
}

let magic = "AUTOMATES"
let version = 1

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

let save_frames
    (type state)
    ~filename
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

  let oc = open_out_bin filename in

  Fun.protect
    ~finally:(fun () -> close_out_noerr oc)
    (fun () ->
       write_string_fixed oc magic;
       write_int oc version;
       write_int oc rows;
       write_int oc cols;
       write_int oc generation;
       write_int oc (Array.length frames);

       Array.iter
         (fun frame ->
            Array.iter
              (fun row ->
                 Array.iter
                   (fun state ->
                      write_int32 oc (Codec.to_int32 state))
                   row)
              frame)
         frames)

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

       if rows <= 0 || cols <= 0 || frame_count < 0 then
         failwith "Io_binary.load_frames: corrupted header";

       let frames =
         Array.init frame_count (fun _ ->
             Array.init rows (fun _ ->
                 Array.init cols (fun _ ->
                     Codec.of_int32 (read_int32 ic))))
       in

       let header = {
         version = file_version;
         rows;
         cols;
         generation;
         frames = frame_count;
       } in

       header, frames)
