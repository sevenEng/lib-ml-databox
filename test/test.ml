open Alcotest
open Lwt.Infix
open Lib_databox

module KV = Store_client.KV
module TS = Store_client.TS

let test_ctx = Utils.databox_init ()
let test_endpoint = "tcp://127.0.0.1:5555"

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

let metas_of_cat cat_json =
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
  let kvc_x = KV.create ~endpoint:test_endpoint test_ctx ?logging () in
  let x_meta = test_meta in
  KV.register_datasource kvc_x ~meta:x_meta >>= fun () ->
  KV.get_datasource_catalogue kvc_x >>= fun cat_raw ->
  let cat_json = Ezjsonm.from_string cat_raw in
  let _, y_meta = List.hd @@ metas_of_cat cat_json in
  let kvc_y = KV.create ~endpoint:test_endpoint test_ctx ?logging () in
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

  let rec check_or_fail d () =
    match d with
    | [] -> Lwt.return_unit
    | c :: tl ->
        Lwt_stream.get stm >>= fun c' ->
        check (option content) "kv streaming observing" (Some c) c';
        check_or_fail tl () in

  Lwt.join [
    check_or_fail kv_l ();
    Lwt_unix.sleep 0.01 >>= fun () ->
    Lwt_list.iter_s (fun payload ->
      KV.write kvc_x ~datasource_id:x_meta.Store_datasource.datasource_id ~payload) kv_l;
  ] >>= fun () ->

  KV.stop_observing kvc_y ~datasource_id:y_meta.Store_datasource.datasource_id >>= fun () ->
  Lwt_stream.get stm >|= check (option content) "exhausted kv stream" None


let setup_ts ?logging () =
  let tsc_x = TS.create ~endpoint:test_endpoint test_ctx ?logging () in
  let x_meta = test_meta in
  TS.register_datasource tsc_x ~meta:x_meta >>= fun () ->
  TS.get_datasource_catalogue tsc_x >>= fun cat_raw ->
  let cat_json = Ezjsonm.from_string cat_raw in
  let _, y_meta = List.hd @@ metas_of_cat cat_json in
  let tsc_y = TS.create ~endpoint:test_endpoint test_ctx ?logging () in
  Lwt.return ((tsc_x, x_meta), (tsc_y, y_meta))

let ezjson =
  let fmt = Fmt.using (Ezjsonm.to_string ~minify:true)  Fmt.string in
  let cmp x y = 0 == Pervasives.compare x y in
  Alcotest.testable fmt cmp

let without_ts o =
  let open Ezjsonm in
  value o
  |> get_dict
  |> List.assoc "data"
  |> fun d -> dict (get_dict d)

let without_ts_arr arr =
  let open Ezjsonm in
  value arr
  |> get_list get_dict
  |> List.map (List.assoc "data")
  |> fun d_arr -> list dict (List.map get_dict d_arr)


let get_ts o =
  let open Ezjsonm in
  value o
  |> get_dict
  |> List.assoc "timestamp"
  |> get_int64

let test_ts_rw ctx () =
  let (tsc_x, x_meta), (tsc_y, y_meta) = ctx in
  let kv_l =
    ["k_rw0", "v_rw0"; "k_rw1", "v_rw1"; "k_rw2", "v_rw2"]
    |> List.map (fun (k, v) -> kv_pair  k v) in
  Lwt_list.iter_s (fun payload ->
    TS.write tsc_x ~datasource_id:x_meta.Store_datasource.datasource_id ~payload) kv_l >>= fun () ->

  TS.latest tsc_y ~datasource_id:y_meta.Store_datasource.datasource_id >>= fun latest ->
  check ezjson "read latest" (kv_pair "k_rw2" "v_rw2") (without_ts latest);
  TS.earliest tsc_y ~datasource_id:y_meta.Store_datasource.datasource_id >>= fun earliest ->
  check ezjson "read earliest" (kv_pair "k_rw0" "v_rw0") (without_ts earliest);
  TS.last_n tsc_y ~datasource_id:y_meta.Store_datasource.datasource_id 2 >>= fun last_n ->
  check ezjson "read last_n" (Ezjsonm.(list value) List.(tl kv_l |> rev)) (without_ts_arr last_n);
  TS.first_n tsc_y ~datasource_id:y_meta.Store_datasource.datasource_id 2 >>= fun last_n ->
  check ezjson "read first_n" (Ezjsonm.(list value) List.(hd kv_l :: (hd @@ tl kv_l) :: [])) (without_ts_arr last_n);
  Lwt.return_unit

let test_ts_write_at ctx () =
  let (tsc_x, x_meta), (tsc_y, y_meta) = ctx in
  let kv = kv_pair "k_w_at" "v_w_at" in
  TS.write tsc_x ~datasource_id:x_meta.Store_datasource.datasource_id ~payload:kv >>= fun () ->
  TS.latest tsc_y ~datasource_id:y_meta.Store_datasource.datasource_id >>= fun latest ->
  let ts, latest = get_ts latest, without_ts latest in
  check ezjson "read latest before write_at" kv latest;
  let kv' = kv_pair "k_w_at" "new_v_w_at" in
  TS.write_at tsc_x ~datasource_id:x_meta.Store_datasource.datasource_id ~ts ~payload:kv' >>= fun () ->
  TS.latest tsc_y ~datasource_id:y_meta.Store_datasource.datasource_id >>= fun latest ->
  check ezjson "read latest after write_at" kv' (without_ts latest);
  Lwt.return_unit

let test_ts_since_range ctx () =
  let (tsc_x, x_meta), (tsc_y, y_meta) = ctx in
  let kv_arr = [|"k_sr0", "v_sr0"; "k_sr1", "v_sr1"; "k_sr2", "v_sr2"; "k_sr3", "v_sr3"|] in
  let k, v = kv_arr.(0) in
  TS.write tsc_x ~datasource_id:x_meta.Store_datasource.datasource_id ~payload:(kv_pair k v) >>= fun () ->
  TS.latest tsc_x ~datasource_id:x_meta.Store_datasource.datasource_id >>= fun latest ->
  let since_ts = Int64.(add one @@ get_ts latest) in
  let rest_lt =
    (Array.sub kv_arr 1 3 |> Array.to_list)
    |> List.map (fun (k, v) -> kv_pair k v) in
  Lwt_list.iter_s (fun payload ->
    TS.write tsc_x ~datasource_id:x_meta.Store_datasource.datasource_id ~payload) rest_lt >>= fun () ->
  TS.since tsc_y ~datasource_id:y_meta.Store_datasource.datasource_id ~since_ts >>= fun since ->
  check ezjson "since" (Ezjsonm.(list value) (List.rev rest_lt)) (without_ts_arr since);
  TS.latest tsc_y ~datasource_id:y_meta.Store_datasource.datasource_id >>= fun latest ->

  let from_ts = since_ts in
  let to_ts = Int64.(add minus_one @@ get_ts latest) in
  TS.range tsc_y ~datasource_id:y_meta.Store_datasource.datasource_id ~from_ts ~to_ts >>= fun range ->
  check ezjson "range" (Ezjsonm.(list value) List.(rev rest_lt |> tl)) (without_ts_arr range);
  Lwt.return_unit

let test_ts_observe ctx () =
  let (tsc_x, x_meta), (tsc_y, y_meta) = ctx in
  let kv_l =
    ["k_ob0", "v_ob0"; "k_ob1", "v_ob1"; "k_ob2", "v_ob2"]
    |> List.map (fun (k, v) -> kv_pair k v) in
  TS.observe tsc_y ~datasource_id:y_meta.Store_datasource.datasource_id () >>= fun stm ->

  Lwt_list.iter_s (fun payload ->
    TS.write tsc_x ~datasource_id:x_meta.Store_datasource.datasource_id ~payload) kv_l >>= fun () ->
  let rec check_or_fail d () =
    match d with
    | [] -> Lwt.return_unit
    | c :: tl ->
        Lwt_stream.get stm >>= fun c' ->
        check (option ezjson) "ts streaming observing" (Some c) c';
        check_or_fail tl () in
  check_or_fail kv_l () >>= fun () ->

  TS.stop_observing tsc_y ~datasource_id:y_meta.Store_datasource.datasource_id >>= fun () ->
  Lwt_stream.get stm >|= check (option ezjson) "ts exhausted stream" None

let run test () = Lwt_main.run @@ test ()
let () =
  let kv_ctx = run setup_kv () in
  let ts_ctx = run setup_ts () in
  let kv_suite = [
    "r/w",     `Quick, run (test_kv_rw kv_ctx);
    "observe", `Slow,  run (test_kv_observe kv_ctx);
  ] in
  let ts_suite = [
    "lastest earliest last_n first_n w/ write", `Quick, run (test_ts_rw ts_ctx);
    "write_at",    `Quick, run (test_ts_write_at ts_ctx);
    "since range", `Slow, run (test_ts_since_range ts_ctx);
    "observe",     `Slow, run (test_ts_observe ts_ctx);
  ] in
  let tests = [
    "kv", kv_suite;
    "ts", ts_suite;
  ] in
  Alcotest.run "core-store" tests