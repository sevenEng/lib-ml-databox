(** [Utils] contains various functions which help
    to initialize a databox context,
    or to retrieve the HTTPS keys,
    or to export data off databox to an external endpoint, etc. *)

type arbiter

type databox_ctx = {
  arbiter: arbiter;
  store_key: string;
  export_endpoint: string;
}

val databox_init : unit -> databox_ctx
(** [databox_init ()] reads some environment variables to set up the context,
    these variables are: DATABOX_ARBITER_ENDPOINT, ARBITER_TOKEN, ZMQ_PUBLIC_KEY,
    if there is no DATABOX_ARBITER_ENDPOINT set, all the access to the store
    will use a default store key and be issued without a token. *)

val store_endpoint : unit -> string
(** [store_endpoint ()] reads environment variable DATABOX_ZMQ_ENDPOINT,
    raise Not_found if the variable is not set. *)

val request_token: arbiter -> host:string -> path:string -> meth:string -> string Lwt.t

val https_creds: unit -> string * string
(** [https_creds ()] returns a tuple of file paths which both point to DATABOX.pem
    file where the HTTPS private and public keys signed by the container managers'
    certificate authority are stored. *)

val export_lp: databox_ctx -> id:string -> destination:string -> payload:string
    -> (Cohttp.Response.t * Cohttp_lwt_body.t) Lwt.t
(** [export_lp ctx ~id ~destination ~payload] allows to export data to an external
    endpoint, its URL is specified by [destination], [payload] should be an escaped
    stringified JSON object.

    If this is a new export request, set [id] to empty string, if need to query
    the export status or the response from the external endpoint, set [id] to the
    ID allocated by export service previously,
    for more: {{:https://github.com/me-box/core-export-service#api} core-export-service}*)