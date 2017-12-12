type arbiter

type databox_ctx = {
  arbiter: arbiter;
  store_endpoint: string;
  store_key: string;
}

val databox_init : unit -> databox_ctx

val request_token: arbiter -> host:string -> path:string -> meth:string -> string Lwt.t

(* returns (cert, priv_key) *)
(* could pass directly to X509_lwt.private_of_pems ~cert ~priv_key *)
val https_creds: unit -> string * string
