type t = Abca_render.Png.color

let black  = (0.0, 0.0, 0.0)
let white  = (1.0, 1.0, 1.0)
let red    = (1.0, 0.0, 0.0)
let green  = (0.0, 1.0, 0.0)
let blue   = (0.0, 0.0, 1.0)
let yellow = (1.0, 1.0, 0.0)
let orange = (1.0, 0.5, 0.0)
let gray   = (0.5, 0.5, 0.5)

let normalize_name s =
  s
  |> String.trim
  |> String.lowercase_ascii

let of_name s =
  match normalize_name s with
  | "black" -> Some black
  | "white" -> Some white
  | "red" -> Some red
  | "green" -> Some green
  | "blue" -> Some blue
  | "yellow" -> Some yellow
  | "orange" -> Some orange
  | "gray" | "grey" -> Some gray
  | _ -> None

let hex_value c =
  match c with
  | '0' .. '9' -> Char.code c - Char.code '0'
  | 'a' .. 'f' -> 10 + Char.code c - Char.code 'a'
  | 'A' .. 'F' -> 10 + Char.code c - Char.code 'A'
  | _ -> invalid_arg "Color.hex_value"

let byte_of_hex s i =
  (16 * hex_value s.[i]) + hex_value s.[i + 1]

let of_hex s =
  let s =
    String.trim s
  in

  let s =
    if String.length s > 0 && s.[0] = '#' then
      String.sub s 1 (String.length s - 1)
    else
      s
  in

  if String.length s <> 6 then
    None
  else
    try
      let r =
        float (byte_of_hex s 0) /. 255.0
      in
      let g =
        float (byte_of_hex s 2) /. 255.0
      in
      let b =
        float (byte_of_hex s 4) /. 255.0
      in
      Some (r, g, b)
    with _ ->
      None

let parse s =
  match of_name s with
  | Some color ->
      color
  | None ->
      match of_hex s with
      | Some color ->
          color
      | None ->
          invalid_arg ("Unknown color: " ^ s)

let to_string (r, g, b) =
  Printf.sprintf
    "#%02X%02X%02X"
    (int_of_float (255.0 *. r))
    (int_of_float (255.0 *. g))
    (int_of_float (255.0 *. b))
