type t;
let endpoint : t => string;

type content_format;
module Response : {
    type t = OK | Unavailable |  Payload string | Observe string string | Error string;
};

let json_format : content_format;
let text_format : content_format;
let binary_format : content_format;

let create_client : endpoint::string => dealer_endpoint::string => server_key::string => logging::bool? => unit => t;

let get: t => token::string? => format::content_format? => uri::string => unit => Lwt.t string;
let post: t => token::string? => format::content_format? => uri::string => payload::string => unit => Lwt.t unit;
let observe: t => token::string? => format::content_format? => uri::string => age::int? => unit => Lwt.t (Lwt_stream.t string);
let stop_observing: t => uri::string => Lwt.t unit;