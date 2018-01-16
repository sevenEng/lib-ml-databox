type meta = {
  description:     string;
  content_type:    string;
  vendor:          string;
  datasource_type: string;
  datasource_id:   string;
  store_type:      [`KV | `TS];
  is_actuator:     bool;
  unit:            string option;
  location:        string option;
}

let string_of_store_type = function
  | `KV -> "kv"
  | `TS -> "ts"
let store_type_of_string str = match String.lowercase_ascii str with
  | "kv" -> `KV
  | "ts" -> `TS
  | _ -> raise @@ Failure ("unknown store type: " ^ str)

let relation (rel,valu) = `O ["rel", `String rel; "val", valu]
let to_hypercat ds_endpoint meta : Ezjsonm.t =
  let mandatory = [
    "urn:X-hypercat:rels:hasDescription:en", `String meta.description;
    "urn:X-hypercat:rels:isContentType", `String meta.content_type;
    "urn:X-databox:rels:hasVendor", `String meta.vendor;
    "urn:X-databox:rels:hasType", `String meta.datasource_type;
    "urn:X-databox:rels:hasDatasourceid", `String meta.datasource_id;
    "urn:X-databox:rels:hasStoreType", `String (string_of_store_type meta.store_type); ] in
  let item_metadata = fun items ->
    (if meta.is_actuator then items @ ["urn:X-databox:rels:isActuator", `Bool meta.is_actuator]
    else items)
    |> fun items -> match meta.unit with
      | Some u -> items @ ["urn:X-databox:rels:hasUnit", `String u]
      | None -> items
    |> fun items -> match meta.location with
      | Some l -> items @ ["urn:X-databox:rels:hasLocation", `String l]
      | None -> items in
  let href = Uri.to_string ds_endpoint in
  let cat = `O [
    "item-metadata", `A (List.map relation @@ item_metadata mandatory);
    "href", `String href;
  ] in
  cat

let from_hypercat cat =
  let open Ezjsonm in
  let cat = value cat |> get_dict in
  let href = List.assoc "href" cat |> get_string in
  let store_endpoint =
    let uri = Uri.of_string href in
    Uri.with_path uri "" in
  let item_metadata =
    List.assoc "item-metadata" cat |> get_list get_dict
    |> List.fold_left (fun acc item ->
        (List.assoc "rel" item |> get_string,
         List.assoc "val" item) :: acc) [] in
  let meta = {
    description = List.assoc "urn:X-hypercat:rels:hasDescription:en" item_metadata |> get_string;
    content_type = List.assoc "urn:X-hypercat:rels:isContentType" item_metadata |> get_string;
    vendor = List.assoc "urn:X-databox:rels:hasVendor" item_metadata |> get_string;
    datasource_type = List.assoc "urn:X-databox:rels:hasType" item_metadata |> get_string;
    datasource_id = List.assoc "urn:X-databox:rels:hasDatasourceid" item_metadata |> get_string;
    store_type = List.assoc "urn:X-databox:rels:hasStoreType" item_metadata |> get_string |> store_type_of_string;
    is_actuator =
      if not @@ List.mem_assoc "urn:X-databox:rels:isActuator" item_metadata then false
      else List.assoc "urn:X-databox:rels:isActuator" item_metadata |> get_bool;
    unit =
      if List.mem_assoc "urn:X-databox:rels:hasUnit" item_metadata
      then Some (List.assoc "urn:X-databox:rels:hasUnit" item_metadata |> get_string)
      else None;
    location =
    if List.mem_assoc "urn:X-databox:rels:hasLocation" item_metadata
    then Some (List.assoc "urn:X-databox:rels:hasLocation" item_metadata |> get_string)
    else None;
  } in
  store_endpoint, meta
