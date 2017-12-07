type t = {
  arbiter_endpoint: Uri.t option;
  arbiter_token: string;
  store_key: string;
}

let secrets_dir = Fpath.v "/run/secrets/"

let arbiter_token () =
  let token_file = Fpath.add_seg secrets_dir "ARBITER_TOKEN" in
  match Bos.OS.File.read token_file with
  | Ok token -> B64.encode token
  | Error (`Msg msg) -> raise @@ Failure msg

let store_key () =
  let key_file = Fpath.add_seg secrets_dir "ZMQ_PUBLIC_KEY" in
  match Bos.OS.File.read key_file with
  | Ok key -> key
  | Error (`Msg msg) -> raise @@ Failure msg

let databox_init () : t =
  let arbiter_endpoint =
    try
      let endp = Sys.getenv "DATABOX_ARBITER_ENDPOINT" in
      Some (Uri.of_string endp)
    with _ -> None in
  if arbiter_endpoint = None then
    {arbiter_endpoint; arbiter_token = ""; store_key = ""}
  else
    let arbiter_token = arbiter_token () in
    let store_key = store_key () in
    {arbiter_endpoint; arbiter_token; store_key}

let create ~arbiter_endpoint ~arbiter_token ~store_key =
  {arbiter_endpoint; arbiter_token; store_key}