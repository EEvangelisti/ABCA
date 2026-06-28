(* cell.ml *)

type state = int

type flags = {
  active  : bool;
  dirty   : bool;
  blocked : bool;
}

type metadata = (string * string) list

type t = {
  state    : state;
  flags    : flags;
  metadata : metadata;
}

let default_flags = {
  active  = false;
  dirty   = false;
  blocked = false;
}

let empty = {
  state    = 0;
  flags    = default_flags;
  metadata = [];
}

let create
    ?(active = false)
    ?(dirty = false)
    ?(blocked = false)
    ?(metadata = [])
    state =
  {
    state;
    flags = { active; dirty; blocked };
    metadata;
  }

let state c =
  c.state

let flags c =
  c.flags

let metadata c =
  c.metadata

let is_empty c =
  c.state = 0 && c.metadata = [] && c.flags = default_flags

let is_active c =
  c.flags.active

let is_dirty c =
  c.flags.dirty

let is_blocked c =
  c.flags.blocked

let with_state state c =
  { c with state; flags = { c.flags with dirty = true } }

let with_flags flags c =
  { c with flags }

let with_metadata metadata c =
  { c with metadata }

let set_active active c =
  { c with flags = { c.flags with active } }

let set_dirty dirty c =
  { c with flags = { c.flags with dirty } }

let set_blocked blocked c =
  { c with flags = { c.flags with blocked } }

let add_metadata key value c =
  let metadata =
    (key, value)
    :: List.remove_assoc key c.metadata
  in
  { c with metadata }

let remove_metadata key c =
  { c with metadata = List.remove_assoc key c.metadata }

let metadata_opt key c =
  List.assoc_opt key c.metadata

let clear_metadata c =
  { c with metadata = [] }

let equal a b =
  a.state = b.state
  && a.flags = b.flags
  && a.metadata = b.metadata
