type databox_ctx = {
  arbiter_endpoint: Uri.t option;
  arbiter_token: string;
  store_endpoint: string;
  store_key: string;
}

val databox_init : unit -> databox_ctx

val request_token: databox_ctx -> host:string -> path:string -> meth:string -> string Lwt.t

(* returns (cert, priv_key) *)
(* could pass directly to X509_lwt.private_of_pems ~cert ~priv_key *)
val https_creds: unit -> string * string
