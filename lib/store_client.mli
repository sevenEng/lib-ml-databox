(** [Store_client] provides the interface to interact with a databox store,
    for both drivers and apps. *)

(** {1 Key-value store} *)

(** Type for content format to be written into a key-value store. *)
type content_format = [`Json | `Text | `Binary]

(** Type for content to be written into a key-value store. *)
type content = [`Json of Ezjsonm.t | `Text of string | `Binary of string]


(** Module type for the key-value store,
    the [datasource_id] could be read from a value of {!Store_datasource.meta} *)
module type KV_SIG = sig

  type t

  val create: endpoint:string -> Utils.databox_ctx -> ?logging:bool -> unit -> t
  (** [create store_uri ctx ?logging ()] creates a key-value store instance.
      [store_uri] could be read from {!Utils.store_endpoint}, [ctx] could be returned
      from {!Utils.databox_init}, [logging] defaults to [false]. *)

  val register_datasource : t -> meta:Store_datasource.meta -> unit Lwt.t
  (** [register_datasource t ~meta] registers a datasource described by [meta]
      with store [t]. *)

  val get_datasource_catalogue : t -> string Lwt.t
  (** [get_datasource_catalogue t] retrieves a summury of all datasources
      registered with store [t]. *)

  (** {1 Store data function} *)

  val write: t -> datasource_id:string -> payload:content -> unit Lwt.t

  (** {1 Load data functions} *)

  val read: t -> datasource_id:string -> ?format:content_format -> unit -> content Lwt.t

  val observe: t -> datasource_id:string -> ?timeout:int -> ?format:content_format -> unit -> content Lwt_stream.t Lwt.t
  (** [observe t ~datasource_id ?timeout ?format ()] returns a stream from which any update on
      the value associated with [datasource_id] is returned.

      [timeout] defaults to 0, which means observing until {!KV_SIG.stop_observing} is called,
      unit is seconds. [format] defaults to `Json. *)

  val stop_observing : t -> datasource_id:string -> unit Lwt.t
end

(** A key-value store implementation which fulfills {!KV_SIG} *)
module KV : KV_SIG


(** {1 Timeseries store} *)

(** Module type for timeeseries store,
    this type of store currently only takes data in JSON format,
    timestamps are in milliseconds since epoch time,
    the [datasource_id] could be read from a value of {!Store_datasource.meta} *)
module type TS_SIG = sig

  type t

  val create: endpoint:string -> Utils.databox_ctx -> ?logging:bool -> unit -> t
  (** [create store_uri ctx ?logging ()] creates a timeseries store instance.
    [store_uri] could be read from {!Utils.store_endpoint}, [ctx] could be returned
    from {!Utils.databox_init}, [logging] defaults to [false]. *)

  val register_datasource : t -> meta:Store_datasource.meta -> unit Lwt.t
  (** See {!KV_SIG.register_datasource}. *)

  val get_datasource_catalogue : t -> string Lwt.t
  (** See {!KV_SIG.get_datasource_catalogue}. *)

  (** {1:store Store data functions} *)

  val write: t -> datasource_id:string -> payload:Ezjsonm.t -> unit Lwt.t

  val write_at: t -> datasource_id:string -> ts:int64 -> payload:Ezjsonm.t -> unit Lwt.t

  (** {1 Load data functions}
      All data loaded will be attached with a timestamp, for example:
      {v
\{ timestamp: 1516633601325,
  data: \[
    \{temperature: 10.7, long:-0.127758, lat:51.507351, loc: "London" \},
    \{temperature: -4.1, long:116.407396 lat:39.904200, loc: "Beijing"\},
    \{temperature: 5.6, long:-122.332071 lat:47.606209, loc: "Seattle"\},
  \]
\}
      v}
      Data from [data] field above is whatever data written into the store by {{!store} the write functions}.
      For functions {!last_n}, {!first_n}, {!since}, {!range}, the returned result
      will be an array of elements of such format. *)

  val latest : t -> datasource_id:string -> Ezjsonm.t Lwt.t

  val earliest : t -> datasource_id:string -> Ezjsonm.t Lwt.t

  val last_n: t -> datasource_id:string -> int -> Ezjsonm.t Lwt.t

  val first_n: t -> datasource_id:string -> int -> Ezjsonm.t Lwt.t

  val since: t -> datasource_id:string -> since_ts:int64 -> Ezjsonm.t Lwt.t

  val range: t -> datasource_id:string -> from_ts:int64 -> to_ts:int64 -> Ezjsonm.t Lwt.t
  (** [range t ~datasource_id ~from_ts ~to_ts], the [from_ts] and [to_ts] are both inclusive
      when the store loads the data*)

  val observe: t -> datasource_id:string -> ?timeout:int -> unit -> Ezjsonm.t Lwt_stream.t Lwt.t
  (** [observe t ~datasource_id ?timeout ()] returns a stream from which each new
      value written to [datasource_id] could be feteched.

      [timeout] defaults to 0, which means observing until {!TS_SIG.stop_observing} is called,
      unit is seconds.*)

  val stop_observing : t -> datasource_id:string -> unit Lwt.t
end

(** A timeseries store implementation which fulfills {!TS_SIG} *)
module TS : TS_SIG