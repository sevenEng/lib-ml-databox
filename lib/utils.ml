open Lwt.Infix

type arbiter = {
  arbiter_endpoint: Uri.t option;
  arbiter_token: string;
  token_cache: (string * string * string, string) Hashtbl.t;
}

type databox_ctx = {
  arbiter: arbiter;
  store_key: string;
  export_endpoint: string;
}

let secrets_dir = Fpath.v "/run/secrets/"

let arbiter_token () =
  let token_file = Fpath.add_seg secrets_dir "ARBITER_TOKEN" in
  match Bos.OS.File.read token_file with
  | Ok token -> B64.encode token
  | Error (`Msg msg) -> raise @@ Failure msg

let store_endpoint () = Sys.getenv "DATABOX_ZMQ_ENDPOINT"

let store_key () =
  let key_file = Fpath.add_seg secrets_dir "ZMQ_PUBLIC_KEY" in
  match Bos.OS.File.read key_file with
  | Ok key -> key
  | Error (`Msg msg) -> raise @@ Failure msg

let export_endpoint () = Sys.getenv "DATABOX_EXPORT_SERVICE_ENDPOINT"

let databox_init () : databox_ctx =
  let arbiter_endpoint =
    try
      let endp = Sys.getenv "DATABOX_ARBITER_ENDPOINT" in
      Some (Uri.of_string endp)
    with _ -> None in
  if arbiter_endpoint = None then
    let arbiter = {
      arbiter_endpoint;
      arbiter_token = "";
      token_cache = Hashtbl.create 23; } in
    let store_key = "vl6wu0A@XP?}Or/&BR#LSxn>A+}L)p44/W[wXL3<" in
    let export_endpoint = "" in
    (*let () = Printf.printf "databox_init: {arbiter: None, store key: %s}\n%!" store_key in*)
    { arbiter; store_key; export_endpoint}
  else
    let arbiter_token = arbiter_token () in
    let arbiter = {
      arbiter_endpoint;
      arbiter_token;
      token_cache = Hashtbl.create 23; } in
    let store_key = store_key () in
    let export_endpoint = export_endpoint () in
    (*let () =
      let endp =
        match arbiter_endpoint with
        | Some uri -> Uri.to_string uri
        | None -> assert false in
      Printf.printf "databox_init: {arbiter: %s, store key: %s}\n%!" endp store_key in*)
    {arbiter; store_key; export_endpoint}


let with_store_key t store_key = {t with store_key}
let store_key {store_key} = store_key

module Client = Cohttp_lwt_unix.Client

let body_of_json json =
  Cohttp_lwt_body.of_string @@ Ezjsonm.to_string json

let headers = Cohttp.Header.init_with "Content-Type" "application/json"

let check_cache t host path meth =
  try Some (Hashtbl.find t.token_cache (host, path, meth))
  with Not_found -> None

let clear_entry t timeout host path meth =
  Lwt_unix.sleep timeout >>= fun () ->
  Hashtbl.remove t.token_cache (host, path, meth);
  Lwt.return_unit

let request_token t ~host ~path ~meth =
  let headers = Cohttp.Header.add headers "x-api-key" t.arbiter_token in
  match t.arbiter_endpoint with
  | None ->  Lwt.return ""
  | Some arbiter_endpoint ->
    match check_cache t host path meth with
    | Some cached -> Lwt.return cached
    | None ->
        let uri = Uri.with_path arbiter_endpoint "/token" in
        let body = `O [
          "target", `String host;
          "path", `String path;
          "method", `String meth
        ] |> body_of_json in
        Lwt_log.debug_f "request_token: for %s %s..." host path >>= fun () ->
        Client.post ~body ~headers uri >>= fun (resp, body) ->
        if Cohttp.Response.status resp <> `OK then
          Cohttp_lwt_body.to_string body >>= fun body ->
          let resp_code = Cohttp.Response.status resp |> Cohttp.Code.string_of_status in
          let failure = Printf.sprintf "%s %s %s\nfor %s %s %s"
          (Uri.to_string uri) resp_code body meth host path in
          Lwt.fail @@ Failure failure
        else begin
          Cohttp_lwt_body.to_string body >>= fun token ->
          Hashtbl.add t.token_cache (host, path, meth) token;
          Lwt.async (fun () -> clear_entry t 120. host path meth);
          Lwt.return token
        end

let https_creds () =
  let cert = Fpath.add_seg secrets_dir "DATABOX.pem" in
  let priv_key = Fpath.add_seg secrets_dir "DATABOX.pem" in
  Fpath.to_string cert, Fpath.to_string priv_key


let to_export_body ?id destination payload =
  let id = match id with Some id -> id | None -> "" in
  let o = [
    "id", `String id;
    "uri", `String destination;
    "data", `String payload ] in
  Ezjsonm.dict o
  |> Ezjsonm.to_string

let export_lp t ~id ~destination ~payload =
  let uri = Uri.of_string t.export_endpoint in
  let host = Uri.host_with_default ~default:"" uri in
  let path = "/lp/export" in
  let meth = "POST" in
  request_token t.arbiter ~host ~path ~meth >>= fun token ->
  let headers = Cohttp.Header.add headers "x-api-key" token in
  let body_str = to_export_body ?id destination payload in
  Lwt_log.debug_f "export_lp: %s" body_str >>= fun () ->
  let body = Cohttp_lwt_body.of_string body_str in
  Client.post ~headers ~body uri