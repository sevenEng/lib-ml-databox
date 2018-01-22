(** [Utils] contains various functions which help to initialize a databox context,
    to retrieve the HTTPS keys, etc. *)

type arbiter

type databox_ctx = {
  arbiter: arbiter;
  store_key: string;
}

val databox_init : unit -> databox_ctx
(** [databox_init ()] read some environment variables to set up the context,
    these variables are: DATABOX_ARBITER_ENDPOINT, ARBITER_TOKEN, ZMQ_PUBLIC_KEY,
    if there is no DATABOX_ARBITER_ENDPOINT set, all the access to the store
    will use a default store key and be issued without a token. *)

val request_token: arbiter -> host:string -> path:string -> meth:string -> string Lwt.t

val https_creds: unit -> string * string
(** [https_creds ()] returns a tuple of file paths which both point to DATABOX.pem
    file where the HTTPS private and public keys signed by the container managers'
    certificate authority are stored. *)

val store_endpoint : unit -> string
(** [store_endpoint ()] reads environment variable DATABOX_ZMQ_ENDPOINT,
    raise Not_found if the variable is not set. *)