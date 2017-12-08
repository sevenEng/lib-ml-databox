type meta = {
  description : string;
  content_type : string;
  vendor : string;
  datasource_type : string;
  datasource_id : string;
  store_type : [`KV | `TS];
  is_actuator : bool;
  unit : string option;
  location : string option;
}

val to_hypercat : Uri.t -> meta -> Ezjsonm.t
val from_hypercat : Ezjsonm.t -> Uri.t * meta
