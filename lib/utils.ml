open Lwt.Infix

type databox_ctx = {
  arbiter_endpoint: Uri.t option;
  arbiter_token: string;
  store_endpoint: string;
  store_key: string;
}

let secrets_dir = Fpath.v "/run/secrets/"

let arbiter_token () =
  let token_file = Fpath.add_seg secrets_dir "ARBITER_TOKEN" in
  match Bos.OS.File.read token_file with
  | Ok token -> B64.encode token
  | Error (`Msg msg) -> raise @@ Failure msg

let store_endpoint () =
  try Sys.getenv "DATABOX_ZMQ_ENDPOINT"
  with Not_found -> ""

let store_key () =
  let key_file = Fpath.add_seg secrets_dir "ZMQ_PUBLIC_KEY" in
  match Bos.OS.File.read key_file with
  | Ok key -> key
  | Error (`Msg msg) -> raise @@ Failure msg

let databox_init () : databox_ctx =
  let arbiter_endpoint =
    try
      let endp = Sys.getenv "DATABOX_ARBITER_ENDPOINT" in
      Some (Uri.of_string endp)
    with _ -> None in
  if arbiter_endpoint = None then
    {arbiter_endpoint; arbiter_token = "";
     store_endpoint = "tcp://127.0.0.1:5555";
     store_key = "vl6wu0A@XP?}Or/&BR#LSxn>A+}L)p44/W[wXL3<"}
  else
    let arbiter_token = arbiter_token () in
    let store_endpoint = store_endpoint () in
    let store_key = store_key () in
    {arbiter_endpoint; arbiter_token; store_endpoint; store_key}


let with_store_key t store_key = {t with store_key}
let store_key {store_key} = store_key

let with_store_endpoint t store_endpoint = {t with store_endpoint}
let store_endpoint {store_endpoint} = store_endpoint

module Client = Cohttp_lwt_unix.Client

let body_of_json json =
  Cohttp_lwt_body.of_string @@ Ezjsonm.to_string json

let headers = Cohttp.Header.init_with "Content-Type" "application/json"

let request_token t ~host ~path ~meth =
  let headers = Cohttp.Header.add headers "x-api-key" t.arbiter_token in
  match t.arbiter_endpoint with
  | None ->  Lwt.return ""
  | Some arbiter_endpoint ->
    let uri = Uri.with_path arbiter_endpoint "/token" in
    let body = `O [
      "target", `String host;
      "path", `String path;
      "method", `String meth
    ] |> body_of_json in
    Client.post ~body ~headers uri >>= fun (resp, body) ->
    if Cohttp.Response.status resp <> `OK
    then Lwt.fail @@ Failure (Uri.to_string uri)
    else Cohttp_lwt_body.to_string body

let https_creds () =
  let cert = Fpath.add_seg secrets_dir "DATABOX.pem" in
  let priv_key = Fpath.add_seg secrets_dir "DATABOX.pem" in
  Fpath.to_string cert, Fpath.to_string priv_key
