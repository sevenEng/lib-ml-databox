(* if arbiter_token = None ->
   each store request will be invoded without
   querying a token from arbiter first*)
type t = {
  arbiter_endpoint: Uri.t option;
  arbiter_token: string;
  store_key: string;
}

val databox_init : unit -> t
