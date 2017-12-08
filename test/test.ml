open Alcotest
open Lwt.Infix

module KV = Store_client.KV
module TS = Store_client.TS

let test_ctx =
  let open Store_client_ctx in {
    arbiter_endpoint = None;
    arbiter_token = "";
    store_key = "vl6wu0A@XP?}Or/&BR#LSxn>A+}L)p44/W[wXL3<"
  }

let endpoint = "tcp://127.0.0.1:5555"

let test_meta =
  let open Store_datasource in
  let description = "test datasource" in
  let content_type = "application/json" in
  let vendor = "lib-ml-databox" in
  let datasource_type = "test-type" in
  let datasource_id = "test" in
  let store_type = `KV in
  let is_actuator = false in
  let unit = None and location = None in
  {description; content_type; vendor;
   datasource_type; datasource_id; store_type;
   is_actuator; unit; location}

let test_actuator_meta =
  let datasource_type = "test-actuator-type" in
  let datasource_id = "actuator" in
  let is_actuator = true in
  {test_meta with datasource_type; datasource_id; is_actuator}

let kv_pair k v =
  let open Ezjsonm in
  ["key", string k; "value", string v]
  |> dict

let hypers_of_cat cat_json =
  let open Ezjsonm in
  get_dict cat_json
  |> List.assoc "items"
  |> get_list get_dict
  |> List.map (fun l -> Store_datasource.from_hypercat (dict l))

let string_of_content = function
  | `Json o -> "Json: " ^ Ezjsonm.to_string o
  | `Text t -> "Text: " ^ t
  | `Binary b -> "Binary: " ^ b

let content : Store_client.content Alcotest.testable =
  let fmt = Fmt.using string_of_content Fmt.string in
  let cmp x y = 0 == Pervasives.compare x y in
  Alcotest.testable fmt cmp

let setup_kv ?logging () =
  let kvc_x = KV.create ~endpoint test_ctx ?logging () in
  let x_meta = test_meta in
  KV.register_datasource kvc_x ~meta:x_meta >>= fun () ->
  KV.get_datasource_catalogue kvc_x >>= fun cat_raw ->
  let cat_json = Ezjsonm.from_string cat_raw in
  let uri, y_meta = List.hd @@ hypers_of_cat cat_json in
  let kvc_y = KV.create ~endpoint:(Uri.to_string uri) test_ctx ?logging () in
  Lwt.return ((kvc_x, x_meta), (kvc_y, y_meta))

let test_kv_rw ctx () =
  let (kvc_x, x_meta), (kvc_y, y_meta) = ctx in
  let k, v = "key", "value" in
  let payload = `Json (kv_pair k v) in
  KV.write kvc_x ~datasource_id:x_meta.Store_datasource.datasource_id ~payload >>= fun () ->
  KV.read kvc_y ~datasource_id:y_meta.Store_datasource.datasource_id ~format:`Json () >>= fun c ->
  check content "read/write values" payload c;
  Lwt.return_unit

let test_kv_observe ctx () =
  let (kvc_x, x_meta), (kvc_y, y_meta) = ctx in
  let kv_l =
    ["k0", "v0"; "k1", "v1"; "k2", "v2"]
    |> List.map (fun (k, v) -> `Json (kv_pair  k v)) in
  KV.observe kvc_y ~datasource_id:y_meta.Store_datasource.datasource_id ~format:`Json () >>= fun stm ->
  let rec observe stm l =
    if l = [] then KV.stop_observing kvc_y ~datasource_id:y_meta.Store_datasource.datasource_id else
    Lwt_stream.get stm >>= function
    | Some c ->
      check content "read value from observe stream" c @@ List.hd l;
      observe stm @@ List.tl l
    | None ->
      check reject "" [] l;
      Lwt.return_unit in
  let write l =
    Lwt_list.iter_s (fun payload ->
      KV.write kvc_x ~datasource_id:x_meta.Store_datasource.datasource_id ~payload) l in
  Lwt.join [write kv_l; observe stm kv_l]

let run test () = Lwt_main.run @@ test ()
let () =
  let kv_ctx = Lwt_main.run @@ setup_kv () in
  let kv_suite = [
    "r/w",     `Quick, run (test_kv_rw kv_ctx);
    "observe", `Slow, run (test_kv_observe kv_ctx);
  ] in
  let tests = [
    "kv", kv_suite;
  ] in
  Alcotest.run "test" tests