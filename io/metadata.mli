type t = (string * string) list
(** Collection of key-value metadata entries.
    Keys are unique; adding an existing key replaces its previous value. *)

val empty : t
(** Empty metadata collection. *)

val add : string -> string -> t -> t
(** Adds or replaces a metadata entry. *)

val get : string -> t -> string option
(** Returns the value associated with a key, if present. *)

val of_list : (string * string) list -> t
(** Builds a metadata collection from a list of key-value pairs.
    If a key appears multiple times, the last occurrence is retained. *)

val to_list : t -> (string * string) list
(** Returns the metadata as a list of key-value pairs. *)

val to_json : t -> string
(** Serializes the metadata as a JSON object. *)

val of_json : string -> t
(** Creates a metadata collection from a JSON string.
    The current implementation stores the original JSON string as metadata
    rather than parsing it. *)
