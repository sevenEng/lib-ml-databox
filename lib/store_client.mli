type content_format = [`Json | `Text | `Binary]
type content = [`Json of Ezjsonm.t | `Text of string | `Binary of string]

module type KV_SIG = sig
  type t
  val create: endpoint:string -> Utils.store_ctx -> ?logging:bool -> unit -> t
  val write: t -> datasource_id:string -> payload:content -> unit Lwt.t
  val read: t -> datasource_id:string -> ?format:content_format -> unit -> content Lwt.t
  val observe: t -> datasource_id:string -> ?timeout:int -> ?format:content_format -> unit -> content Lwt_stream.t Lwt.t
  val stop_observing : t -> datasource_id:string -> unit Lwt.t
  val register_datasource : t -> meta:Store_datasource.meta -> unit Lwt.t
  val get_datasource_catalogue : t -> string Lwt.t
end

module type TS_SIG = sig
  type t
  val create: endpoint:string -> Utils.store_ctx -> ?logging:bool -> unit -> t
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

module KV : KV_SIG
module TS : TS_SIG