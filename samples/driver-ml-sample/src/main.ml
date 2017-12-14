open Lwt.Infix
open Lib_databox

module TS = Store_client.TS

let feed_meta =
  let open Store_datasource in
  let description     = "feed in sample driver for lib-ml-databox" in
  let content_type    = "application/json" in
  let vendor          = "Databox" in
  let datasource_type = "mlSampleFeed" in
  let datasource_id   = "mlSampleFeed" in
  let store_type      = `TS in
  let is_actuator     = false in
  { description; content_type; vendor;
    datasource_type; datasource_id; store_type;
    is_actuator; unit = None; location = None; }

let actuator_meta =
  let open Store_datasource in
  let description     = "actuator in sample driver for lib-ml-databox" in
  let content_type    = "application/json" in
  let vendor          = "Databox" in
  let datasource_type = "mlSampleActuator" in
  let datasource_id   = "mlSampleActuator" in
  let store_type      = `TS in
  let is_actuator     = true in
  { description; content_type; vendor;
    datasource_type; datasource_id; store_type;
    is_actuator; unit = None; location = None; }

(* f(x) = x^2 - S = 0 *)
(* x_n+1 = x_n - f(x_n) / f'(x_n) = (x_n + S/x_n) / 2 *)
let next s xn = (xn +. s /. xn) /. 2.

let to_req req =
  let open Ezjsonm in
  let o = get_dict (value req) in
  List.assoc "solve" o |> get_float,
  List.assoc "command" o |> get_string

let to_resp s rt =
  let open Ezjsonm in
  let resp = ["solve", float s; "result", float rt] in
  dict resp

let serve_req tsc req_stm =
  let req_q = ref [] in
  let rec extract_req () =
    Lwt_stream.get req_stm >>= function
    | Some req ->
      req_q := (to_req req) :: !req_q;
      Lwt_log.notice_f "got request: %s" (Ezjsonm.to_string req) >>= fun () ->
      extract_req ()
    | None -> Lwt.return_unit in

  let rec compute s xn =
    Lwt_unix.sleep 1. >>= fun () ->
    match s with
    | None ->
        if !req_q = [] then compute None 0. else
          let s, comm = List.hd !req_q in
          let () = req_q := List.tl !req_q in
          if comm != "start" then compute None 0.
          else compute (Some s) (s /. 2.)
    | Some s ->
        let payload = to_resp s xn in
        Lwt_log.notice_f "feed back: %s" (Ezjsonm.to_string payload) >>= fun () ->
        TS.write tsc ~datasource_id:feed_meta.Store_datasource.datasource_id ~payload >>= fun () ->
        if !req_q = [] || List.hd !req_q != (s, "stop") then compute (Some s) (next s xn)
        else (req_q := List.tl !req_q; compute None 0.) in

  extract_req () <&> compute None 0.


let main () =
  let ctx = Utils.databox_init () in
  let endpoint = Utils.store_endpoint () in
  let tsc = TS.create ~endpoint ctx () in
  TS.register_datasource tsc ~meta:feed_meta >>= fun () ->
  TS.register_datasource tsc ~meta:actuator_meta >>= fun () ->

  TS.observe tsc ~datasource_id:actuator_meta.Store_datasource.datasource_id () >>= fun req_stm ->
  Lwt_log.notice "driver-ml-sample started..." >>= fun () ->
  serve_req tsc req_stm

let () = Lwt_main.run @@ main ()
