type color =
  Abca_render.Png.color

type palette =
  Abca_render.Png.palette

type generator = {
  name        : string;
  description : string;
  make        : states:int -> palette;
}

let registry : (string, generator) Hashtbl.t =
  Hashtbl.create 16

let register generator =
  Hashtbl.replace registry generator.name generator

let find name =
  Hashtbl.find_opt registry name

let get name =
  match find name with
  | Some generator ->
      generator
  | None ->
      invalid_arg ("Unknown palette: " ^ name)

let all () =
  registry
  |> Hashtbl.to_seq_values
  |> List.of_seq
  |> List.sort (fun a b ->
      String.compare a.name b.name)

let names () =
  all ()
  |> List.map (fun p -> p.name)

let exists name =
  Hashtbl.mem registry name

let clear () =
  Hashtbl.clear registry
