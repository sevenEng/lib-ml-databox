open Lwt.Infix

module Z = Zest_client

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


module Common = struct
  type store_type = [`KV | `TS]
  type t = {
    zest: Z.t;
    client_ctx: Utils.databox_ctx;
    store_type: store_type;
  }

  let path_root t = match t.store_type with
    | `KV -> "/kv"
    | `TS -> "/ts"
  let with_root t path = (path_root t) ^ path

  let common_write t ~path ?token_path ~payload () =
    let host =
      Z.endpoint t.zest
      |> Uri.of_string
      |> Uri.host_with_default ~default:"" in
    let path = with_root t path in
    let token_path = match token_path with
      | None -> path | Some path -> with_root t path in
    Utils.request_token t.client_ctx.arbiter ~host ~path:token_path ~meth:"POST" >>= fun token ->
    let format, payload = match payload with
      | `Json o -> Z.json_format, Ezjsonm.to_string o
      | `Text t -> Z.text_format, t
      | `Binary b -> Z.binary_format, b in
    Z.post t.zest ~token ~format ~uri:path ~payload ()

  let common_read t ~path ?(format=`Json) () =
    let host =
      Z.endpoint t.zest
      |> Uri.of_string
      |> Uri.host_with_default ~default:"" in
    let path = with_root t path in
    Utils.request_token t.client_ctx.arbiter ~host ~path ~meth:"GET" >>= fun token ->
    Z.get t.zest ~token ~format:(to_format format) ~uri:path ()
    >|= transform_content format

  let observe t ~datasource_id ?(timeout=0) ?(format=`Json) () =
    let host =
      Z.endpoint t.zest
      |> Uri.of_string
      |> Uri.host_with_default ~default:"" in
    let path = with_root t @@ "/" ^ datasource_id in
    Utils.request_token t.client_ctx.arbiter ~host ~path ~meth:"GET"  >>= fun token ->
    Z.observe t.zest ~token ~uri:path ~format:(to_format format) ()
    >|= fun s -> Lwt_stream.from (transform_stream format s)

  let stop_observing t ~datasource_id =
    let path = with_root t @@ "/" ^ datasource_id in
    Z.stop_observing t.zest ~uri:path

  let register_datasource t ~meta =
    let endpoint = Z.endpoint t.zest in
    let host =
      endpoint
      |> Uri.of_string
      |> Uri.host_with_default ~default:"" in
    Lwt_log.debug_f "host: %s\n%!" host >>= fun () ->
    Lwt_log.debug_f "zest endpoint: %s\n%!" endpoint >>= fun () ->
    let path = "/cat" in
    Utils.request_token t.client_ctx.arbiter ~host ~path ~meth:"POST" >>= fun token ->
    let payload =
      let ds_path = with_root t @@ "/" ^ meta.Store_datasource.datasource_id in
      let ds_uri = Uri.with_path (Uri.of_string endpoint) ds_path in
      let cat = Store_datasource.to_hypercat ds_uri meta in
      Ezjsonm.to_string cat in
    Lwt_log.debug_f "payload: %s\n%!" payload >>= fun () ->
    Z.post t.zest ~token ~format:Z.json_format ~uri:path ~payload ()

  let get_datasource_catalogue t =
    let host =
      Z.endpoint t.zest
      |> Uri.of_string
      |> Uri.host_with_default ~default:"" in
    let path = "/cat" in
    Utils.request_token t.client_ctx.arbiter ~host ~path ~meth:"GET" >>= fun token ->
    Z.get t.zest ~token ~uri:path ()

  let create store_type ~endpoint client_ctx ?logging () =
    let dealer_endpoint =
      let endp = Uri.of_string endpoint in
      let d_endp = Uri.with_port endp (Some 5556) in
      Uri.to_string d_endp in
    let server_key = client_ctx.Utils.store_key in
    let zest = Z.create_client ~endpoint ~dealer_endpoint ~server_key ?logging () in
    {zest; client_ctx; store_type}
end

module type KV_SIG = sig
  type t
  val create: endpoint:string -> Utils.databox_ctx -> ?logging:bool -> unit -> t
  val write: t -> datasource_id:string -> payload:content -> unit Lwt.t
  val read: t -> datasource_id:string -> ?format:content_format -> unit -> content Lwt.t
  val observe: t -> datasource_id:string -> ?timeout:int -> ?format:content_format -> unit -> content Lwt_stream.t Lwt.t
  val stop_observing : t -> datasource_id:string -> unit Lwt.t
  val register_datasource : t -> meta:Store_datasource.meta -> unit Lwt.t
  val get_datasource_catalogue : t -> string Lwt.t
end

module KV : KV_SIG = struct
  include Common

  let create = create `KV

  let write t ~datasource_id ~payload =
    let path = "/" ^ datasource_id in
    common_write t ~path ~payload ()

  let read t ~datasource_id ?(format=`Json) () =
    let path = "/" ^ datasource_id in
    common_read t ~path ~format ()
end


module type TS_SIG = sig
  type t
  val create: endpoint:string -> Utils.databox_ctx -> ?logging:bool -> unit -> t
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

  let create = create `TS

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