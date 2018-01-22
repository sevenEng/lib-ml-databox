(** Type for datasource metadata. *)
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
(** {ul
    {- [datasource_id], uniquely identifies this datasource wihtin a databox instance. }
    {- [store_type], indicates which kind of store to put this datasource in, key-value or timeseries. }
    {- [is_actuator], if set to [true], client will have the write access on this datasource. }} *)

val to_hypercat : Uri.t -> meta -> Ezjsonm.t
(** [to_hypercat ds_uri ~meta] generates a hypercat file used internally in a store
    to describe a datasource, [ds_uri] points to the path within the store where
    the datasource locates. *)

val from_hypercat : Ezjsonm.t -> Uri.t * meta
(** [from_hypercat hyper] parses a hypercat file into a tuple, of which
    the first element is the uri path to the store where the datasource resides,
    the second element is the metadata of the datasource. *)