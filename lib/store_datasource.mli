type meta = {
  description : string;
  content_type : string;
  vendor : string;
  datasource_type : string;
  datasource_id : string;
  store_type : string;
  is_actuator : bool;
  unit : string option;
  location : string option;
}

val to_hypercat : Uri.t -> meta -> Ezjsonm.t
val from_hypercat : Ezjsonm.t -> Uri.t * meta

val set_actuator : meta -> bool -> meta
val set_unit : meta -> string option -> meta
val set_location : meta -> string option -> meta

val create_meta :
  description:string ->
  content_type:string ->
  vendor:string ->
  datasource_type:string ->
  datasource_id:string -> store_type:string -> meta