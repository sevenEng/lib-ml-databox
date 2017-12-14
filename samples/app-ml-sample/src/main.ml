open Lwt.Infix
open Lib_databox

module TS = Store_client.TS
module Server = Cohttp_lwt_unix.Server

let metas () =
  let endpoint, feed_meta =
    let hyper_raw = Sys.getenv "DATASOURCE_mlSampleFeed" in
    Ezjsonm.from_string hyper_raw
    |> Store_datasource.from_hypercat in
  let _, actuator_meta =
    let hyper_raw = Sys.getenv "DATASOURCE_mlSampleActuator" in
    Ezjsonm.from_string hyper_raw
    |> Store_datasource.from_hypercat in
  Uri.to_string endpoint, feed_meta, actuator_meta


type app_state = {
  mutable to_solve : float;
  mutable delta: float;
  mutable last: float;
}

type t = {
  app : app_state;
  store : TS.t * Ezjsonm.t Lwt_stream.t * string;
}

let init () =
  let ctx = Utils.databox_init () in
  let endpoint, feed_meta, acutuator_meta = metas () in
  TS.create ~endpoint ctx (),
  feed_meta.Store_datasource.datasource_id,
  acutuator_meta.Store_datasource.datasource_id


let req_of_body body =
  let open Ezjsonm in
  Cohttp_lwt_body.to_string body >>= fun body ->
  from_string body
  |> value
  |> get_dict
  |> fun l -> (List.assoc "rn" l |> get_float, List.assoc "delta" l |> get_float)
  |> Lwt.return

let body_of_results ?(stop = false) results =
  let open Ezjsonm in
  if stop then
    list string ["over"]
    |> Ezjsonm.to_string
    |> Cohttp_lwt_body.of_string
  else
    list float results
    |> Ezjsonm.to_string
    |> Cohttp_lwt_body.of_string

let actu_req s comm =
  let open Ezjsonm in
  let d = ["solve", float s; "command", string comm] in
  dict d

let feed ezj =
  let open Ezjsonm in
  value ezj
  |> get_dict
  |> fun l -> List.assoc "solve" l |> get_float, List.assoc "result" l |> get_float

let empty_body = Cohttp_lwt_body.empty

let should_stop app results =
  if results = [] then false else
  let last' = List.hd results in
  abs_float (app.last -. last') <= app.delta

let callback t conn req body =
  let tsc, feed_stm, actuator_id = t.store in
  let meth = Cohttp.Request.meth req in
  let uri = Cohttp.Request.uri req in
  Lwt_log.notice_f "connection %s: %s %s"
    (Cohttp.Connection.to_string (snd conn))
    (Cohttp.Code.string_of_method meth)
    (Uri.to_string uri) >>= fun () ->
  let path = Uri.path uri |> String.split_on_char '/' |> List.tl in
  match path with
  | ["ui"] ->
    let uri' = Uri.with_path uri "/index.html" in
    let fname = Server.resolve_file ~docroot:"./www" ~uri:uri' in
    Server.respond_file ~fname ()
  | ["ui"; "solve"] ->
    (match meth with
    | `POST ->
      req_of_body body >>= fun (to_solve, delta) ->
      t.app.to_solve <- to_solve;
      t.app.delta <- delta;
      TS.write tsc ~datasource_id:actuator_id ~payload:(actu_req to_solve "start") >>= fun () ->
      Lwt_stream.next feed_stm >>= fun feed_ezj ->
      let _, last = feed feed_ezj in
      t.app.last <- last;
      Server.respond ~status:`OK ~body:empty_body ()
    | `GET ->
      let results =
        Lwt_stream.get_available feed_stm
        |> List.map feed
        |> List.filter (fun (s, _) -> s = t.app.to_solve)
        |> List.map snd in
      if should_stop t.app results then
        TS.write tsc ~datasource_id:actuator_id ~payload:(actu_req t.app.to_solve "stop") >>= fun () ->
        let body = body_of_results ~stop:true results in
        Server.respond ~status:`OK ~body ()
      else
        let () = if results != [] then t.app.last <- List.rev results |> List.hd in
        let body = body_of_results results in
        Server.respond ~status:`OK ~body ()
    | _ -> Server.respond_not_found ())
  | "ui" :: "static" :: tl ->
    let uri' = Uri.with_path uri @@ String.concat "/" tl in
    let fname = Server.resolve_file ~docroot:"./www" ~uri:uri' in
    Server.respond_file ~fname ()
  | _ -> Server.respond_not_found ~uri ()

let main () =
  let tsc, feed_id, actu_id = init () in
  TS.observe tsc ~datasource_id:feed_id () >>= fun stm ->
  let store = tsc, stm, actu_id in
  let app = {to_solve = 0.; delta = 0.; last = 0. } in
  let t = {store; app} in
  let server = Server.make ~callback:(callback t) () in
  let cert, key = Utils.https_creds () in
  let tls_config = `Crt_file_path cert, `Key_file_path key, `No_password, `Port 8080 in
  let mode = `TLS tls_config in
  Lwt_log.notice "app-ml-sample started..." >>= fun () ->
  Server.create ~mode server

let () = Lwt_main.run @@ main ()