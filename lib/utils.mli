type store_ctx

val databox_init : unit -> store_ctx

val with_store_key: store_ctx -> string -> store_ctx
val store_key: store_ctx -> string

val request_token: store_ctx -> host:string -> path:string -> meth:string -> string Lwt.t

(* returns (cert, priv_key) *)
(* could pass directly to X509_lwt.private_of_pems ~cert ~priv_key *)
val https_creds: unit -> string * string
