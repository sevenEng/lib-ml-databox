open Lwt.Infix

module Z = Zest_client

module Store_env = struct

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

  let init () : t =
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
end


type content = [`Json of Ezjsonm.t | `Text of string | `Binary of string]
type content_format = [`Json | `Text | `Binary]
let to_format = function
  | `Json -> Z.json_format
  | `Text -> Z.text_format
  | `Binary -> Z.binary_format

let transform_content f c : content =
  match f with
  | `Json -> `Json (Ezjsonm.from_string c)
  | `Text -> `Text c
  | `Binary -> `Binary c

let transform_stream f s () =
  Lwt_stream.get s >>= function
  | Some str -> Lwt.return (Some (transform_content f str))
  | None -> Lwt.return_none



module Utils = struct
  module Client = Cohttp_lwt_unix.Client

  let body_of_json json =
    Cohttp_lwt_body.of_string @@ Ezjsonm.to_string json

  let headers = Cohttp.Header.init_with "Content-Type" "application/json"

  let request_token (env:Store_env.t) target_host target_path meth =
    match env.arbiter_endpoint with
    | None ->  Lwt.return ""
    | Some arbiter_endpoint ->
      let uri = Uri.with_path arbiter_endpoint "/token" in
      let body = `O [
        "target", `String target_host;
        "path", `String target_path;
        "method", `String meth
      ] |> body_of_json in
      Client.post ~body ~headers uri >>= fun (resp, body) ->
      if Cohttp.Response.status resp <> `OK
      then Lwt.fail @@ Failure (Uri.to_string uri)
      else Cohttp_lwt_body.to_string body
end


module Common = struct
  type store_type = [`KV | `TS]
  type t = {
    zest: Z.t;
    store_env: Store_env.t;
    store_type: store_type;
  }

  let path_root t = match t.store_type with
    | `KV -> "/kv"
    | `TS -> "/ts"
  let with_root t path = (path_root t) ^ path

  let common_write t ~path ?token_path ~payload () =
    let host = Z.endpoint t.zest in
    let path = with_root t path in
    let token_path = match token_path with
      | None -> path | Some path -> with_root t path in
    Utils.request_token t.store_env host token_path "POST" >>= fun token ->
    let uri = Uri.make ~host ~path () |> Uri.to_string in
    let format, payload = match payload with
      | `Json o -> Z.json_format, Ezjsonm.to_string o
      | `Text t -> Z.text_format, t
      | `Binary b -> Z.binary_format, b in
    Z.post t.zest ~token ~format ~uri ~payload ()

  let common_read t ~path ?(format=`Json) () =
    let host = Z.endpoint t.zest in
    let path = with_root t path in
    Utils.request_token t.store_env host path "GET" >>= fun token ->
    let uri = Uri.make ~host ~path () |> Uri.to_string in
    Z.get t.zest ~token ~format:(to_format format) ~uri ()
    >|= transform_content format

  let observe t ~datasource_id ?(timeout=0) ?(format=`Json) () =
    let host = Z.endpoint t.zest in
    let path = with_root t @@ "/" ^ datasource_id in
    Utils.request_token t.store_env host path "GET"  >>= fun token ->
    let uri = Uri.make ~host ~path () |> Uri.to_string in
    Z.observe t.zest ~token ~uri ~format:(to_format format) ()
    >|= fun s -> Lwt_stream.from (transform_stream format s)

  let stop_observing t ~datasource_id =
    let host = Z.endpoint t.zest in
    let path = with_root t @@ "/" ^ datasource_id in
    let uri = Uri.make ~host ~path () |> Uri.to_string in
    Z.stop_observing t.zest ~uri

  let register_datasource t ~meta =
    let host = Z.endpoint t.zest in
    let path = "/cat" in
    Utils.request_token t.store_env host path "POST" >>= fun token ->
    let uri = Uri.make ~host ~path () |> Uri.to_string in
    let payload =
      let ds_path = with_root t @@ "/" ^ meta.Store_datasource.datasource_id in
      let ds_uri = Uri.with_path (Uri.of_string host) ds_path in
      let cat = Store_datasource.to_hypercat ds_uri meta in
      Ezjsonm.to_string cat in
    Z.post t.zest ~token ~format:Z.json_format ~uri ~payload ()

  let get_datasource_catalogue t =
    let host = Z.endpoint t.zest in
    let path = "/cat" in
    Utils.request_token t.store_env host path "GET" >>= fun token ->
    let uri = Uri.make ~host ~path () |> Uri.to_string in
    Z.get t.zest ~token ~uri ()

  let create endpoint store_type =
    let store_env = Store_env.init () in
    let dealer_endpoint =
      let endp = Uri.of_string endpoint in
      let d_endp = Uri.with_port endp (Some 5556) in
      Uri.to_string d_endp in
    let zest = Z.create_client ~endpoint ~dealer_endpoint ~server_key:store_env.store_key in
    {zest; store_env; store_type}
end

module type KV_SIG = sig
  type t
  val create: string -> t
  val write: t -> datasource_id:string -> payload:content -> unit Lwt.t
  val read: t -> datasource_id:string -> ?format:content_format -> unit -> content Lwt.t
  val observe: t -> datasource_id:string -> ?timeout:int -> ?format:content_format -> unit -> content Lwt_stream.t Lwt.t
  val stop_observing : t -> datasource_id:string -> unit Lwt.t
  val register_datasource : t -> meta:Store_datasource.meta -> unit Lwt.t
  val get_datasource_catalogue : t -> string Lwt.t
end

module KV : KV_SIG = struct
  include Common

  let create endpoint = create endpoint `KV

  let write t ~datasource_id ~payload =
    let path = "/" ^ datasource_id in
    common_write t ~path ~payload ()

  let read t ~datasource_id ?(format=`Json) () =
    let path = "/" ^ datasource_id in
    common_read t ~path ~format ()
end


module type TS_SIG = sig
  type t
  val create: string -> t
  val write: t -> datasource_id:string -> payload:Ezjsonm.t -> unit Lwt.t
  val write_at: t -> datasource_id:string -> ts:int64 -> payload:Ezjsonm.t -> unit Lwt.t
  val latest : t -> datasource_id:string -> Ezjsonm.t Lwt.t
  val earliest : t -> datasource_id:string -> Ezjsonm.t Lwt.t
  val last_n: t -> datasource_id:string -> int -> Ezjsonm.t Lwt.t
  val first_n: t -> datasource_id:string -> int -> Ezjsonm.t Lwt.t
  val since: t -> datasource_id:string -> since_ts:int64 -> Ezjsonm.t Lwt.t
  val range: t -> datasource_id:string -> from_ts:int64 -> to_ts:int64 -> Ezjsonm.t Lwt.t
  val observe: t -> datasource_id:string -> ?timeout:int -> unit -> Ezjsonm.t Lwt_stream.t Lwt.t
  val stop_observing : t -> datasource_id:string -> unit Lwt.t
  val register_datasource : t -> meta:Store_datasource.meta -> unit Lwt.t
  val get_datasource_catalogue : t -> string Lwt.t
end

module TS : TS_SIG = struct
  include Common

  let create endpoint = create endpoint `TS

  let write t ~datasource_id ~payload =
    let path = "/" ^ datasource_id in
    common_write t ~path ~payload:(`Json payload) ()

  let write_at t ~datasource_id ~ts ~payload =
    let path = Printf.sprintf "/%s/at/%s" datasource_id (Int64.to_string ts) in
    let token_path = Printf.sprintf "/%s/at/*" datasource_id in
    common_write t ~path ~token_path ~payload:(`Json payload) ()

  let extract_json_payload = function
    | `Json o -> Lwt.return o
    | #content -> Lwt.fail (Failure "text/binary payload from timeseries client")

  let extract_json_stream (s:content Lwt_stream.t) =
    Lwt_stream.from (fun () ->
      Lwt_stream.get s >>= function
        | Some (`Json o) -> Lwt.return (Some o)
        | Some _ | None -> Lwt.return None)

  let latest t ~datasource_id =
    let path = Printf.sprintf "/%s/latest" datasource_id in
    common_read t  ~path ~format:`Json () >>= extract_json_payload

  let earliest t ~datasource_id =
    let path = Printf.sprintf "/%s/earliest" datasource_id in
    common_read t  ~path ~format:`Json () >>= extract_json_payload

  let last_n t ~datasource_id n =
    let path = Printf.sprintf "/%s/last/%d" datasource_id n in
    common_read t  ~path ~format:`Json () >>= extract_json_payload

  let first_n t ~datasource_id n =
    let path = Printf.sprintf "/%s/first/%d" datasource_id n in
    common_read t  ~path ~format:`Json () >>= extract_json_payload

  let since t ~datasource_id ~since_ts =
    let path = Printf.sprintf "/%s/since/%s" datasource_id (Int64.to_string since_ts) in
    common_read t  ~path ~format:`Json () >>= extract_json_payload

  let range t ~datasource_id ~from_ts ~to_ts =
    let path = Printf.sprintf "/%s/range/%s/%s" datasource_id (Int64.to_string from_ts) (Int64.to_string to_ts) in
    common_read t  ~path ~format:`Json () >>= extract_json_payload

  let observe t ~datasource_id ?timeout () =
    observe t ~datasource_id ?timeout ~format:`Json () >|= extract_json_stream
end