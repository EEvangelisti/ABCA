(* io_xml.ml *)

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
    invalid_arg "Io_xml: invalid frame row count";

  Array.iter
    (fun row ->
       if Array.length row <> cols then
         invalid_arg "Io_xml: invalid frame column count")
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
       Printf.fprintf oc "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";

       Printf.fprintf oc
         "<automates model=\"%s\" rows=\"%d\" cols=\"%d\" generation=\"%d\" frames=\"%d\">\n"
         (xml_escape model)
         rows
         cols
         generation
         (Array.length frames);

       Array.iteri
         (fun frame_index frame ->
            Printf.fprintf oc "  <frame index=\"%d\">\n" frame_index;

            Array.iteri
              (fun row cells ->
                 Array.iteri
                   (fun col state ->
                      let s = Codec.to_string state in

                      if s <> "0" && s <> "." && s <> "" then
                        Printf.fprintf oc
                          "    <cell row=\"%d\" col=\"%d\" state=\"%s\" />\n"
                          row
                          col
                          (xml_escape s))
                   cells)
              frame;

            Printf.fprintf oc "  </frame>\n")
         frames;

       Printf.fprintf oc "</automates>\n")
