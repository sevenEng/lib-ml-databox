open Lwt.Infix;

type t = {
  zmq_ctx: ZMQ.Context.t,
  endpoint: string,
  dealer_endpoint: string,
  request_socket: Lwt_zmq.Socket.t [ `Req ],
  mutable observers: list (string, Lwt_zmq.Socket.t [ `Dealer ]),
};

let endpoint (t: t) => t.endpoint;

type content_format = string;

let create_content_format id => {
  let bits = [%bitstring {|id : 16 : bigendian|}];
  Bitstring.string_of_bitstring bits
};

let json_format = create_content_format 50;
let text_format = create_content_format 0;
let binary_format = create_content_format 42;


module Response = {
    type t = OK | Unavailable |  Payload string | Observe string string | Error string;
};

let string_of_response resp => {
  open Response;
  switch resp {
  | OK => "OK";
  | Unavailable => "Unavailable";
  | Payload p => "Payload " ^ p;
  | Observe k p => "Observe " ^ k ^ " " ^ p;
  | Error err => "Error " ^ err;
  };
};

let setup_logger () => {
  Lwt_log_core.default :=
    Lwt_log.channel
      template::"$(date).$(milliseconds) [$(level)] $(message)"
      close_mode::`Keep
      channel::Lwt_io.stdout
      ();
  Lwt_log_core.add_rule "*" Lwt_log_core.Debug;
};

let to_hex msg => {
  open Hex;
  String.trim (of_string msg |> hexdump_s print_chars::false);
};

let handle_header bits => {
  let tuple = [%bitstring
    switch bits {
    | {|code : 8 : unsigned;
        oc : 8 : unsigned;
        tkl : 16 : bigendian;
        rest : -1 : bitstring
     |} => (tkl, oc, code, rest);
    | {|_|} => failwith "invalid header";
    };
  ];
  tuple;
};

let handle_option bits => {
  let tuple = [%bitstring
    switch bits {
    | {|number : 16 : bigendian;
        len : 16 : bigendian;
        value: len*8: string;
        rest : -1 : bitstring
      |} => (number, value, rest);
    | {|_|} => failwith "invalid options";
    };
  ];
  tuple;
};

let handle_options oc bits => {
  let options = Array.make oc (0,"");
  let rec handle oc bits =>
    if (oc == 0) {
      bits;
    } else {
      let (number, value, r) = handle_option bits;
      Array.set options (oc - 1) (number,value);
      let _ = Lwt_log_core.debug_f "option => %d:%s" number value;
      handle (oc - 1) r
  };
  (options, handle oc bits);
};

let has_public_key options => {
  if (Array.exists (fun (number,_) => number == 2048) options) {
    true;
  } else {
    false;
  }
};

let get_option_value options value => {
  let rec find a x i => {
    let (number,value) = a.(i);
    if (number == x) {
      value;
    } else {
      find a x (i + 1)
    };
  };
  find options value 0;
};

let handle_ack_content options payload => {
  let payload = Bitstring.string_of_bitstring payload;
  if (has_public_key options) {
    let key = get_option_value options 2048;
    Response.Observe key payload |> Lwt.return;
  } else {
    Response.Payload payload |> Lwt.return;
  };
};

let handle_ack_created options => {
  Response.OK |> Lwt.return;
};

let handle_service_unavailable options => {
  Response.Unavailable |> Lwt.return;
};

let handle_ack_bad_request options => {
  Response.Error "Bad Request" |> Lwt.return;
};

let handle_unsupported_content_format options => {
  Response.Error "Unsupported Content-Format" |> Lwt.return;
};

let handle_ack_unauthorized options => {
  Response.Error "Unauthorized" |> Lwt.return;
};

let handle_response ::msg => {
  Lwt_log_core.debug_f "Received:\n%s" (to_hex msg) >>=
    fun () => {
      let r0 = Bitstring.bitstring_of_string msg;
      let (tkl, oc, code, r1) = handle_header r0;
      let (options,payload) = handle_options oc r1;
      switch code {
      | 69 => handle_ack_content options payload;
      | 65 => handle_ack_created options;
      | 128 => handle_ack_bad_request options;
      | 129 => handle_ack_unauthorized options;
      | 143 => handle_unsupported_content_format options;
      | 163 => handle_service_unavailable options;
      | _ => failwith ("invalid code:" ^ string_of_int code);
      };
    };
};

let send_request msg::msg to::socket => {
  Lwt_log_core.debug_f "Sending:\n%s" (to_hex msg) >>=
    fun () =>
      Lwt_zmq.Socket.send socket msg >>=
        fun () =>
          Lwt_zmq.Socket.recv socket >>=
            fun msg =>
              handle_response ::msg;
};

let create_header tkl::tkl oc::oc code::code => {
  let bits = [%bitstring
    {|code : 8 : unsigned;
      oc : 8 : unsigned;
      tkl : 16 : bigendian
    |}
  ];
  (bits, 32);
};

let create_option number::number value::value => {
  let byte_length = String.length value;
  let bit_length = byte_length * 8;
  let bits = [%bitstring
    {|number : 16 : bigendian;
      byte_length : 16 : bigendian;
      value : bit_length : string
    |}
  ];
  (bits ,(bit_length+32));
};

let create_token tk::token => {
  let bit_length = (String.length token) * 8;
  (token, bit_length);
};

let create_options options => {
  let count = Array.length options;
  let values = Array.map (fun (x,y) => x) options;
  let value = Bitstring.concat (Array.to_list values);
  let lengths = Array.map (fun (x,y) => y) options;
  let length = Array.fold_left (fun x y => x + y) 0 lengths;
  (value, length, count);
};

let create_post_options uri::uri format::format => {
  let uri_path = create_option number::11 value::uri;
  let uri_host = create_option number::3 value::(Unix.gethostname ());
  let content_format = create_option number::12 value::format;
  create_options [|uri_path, uri_host, content_format|];
};

let create_get_options uri::uri format::format => {
  let uri_path = create_option number::11 value::uri;
  let uri_host = create_option number::3 value::(Unix.gethostname ());
  let content_format = create_option number::12 value::format;
  create_options [|uri_path, uri_host, content_format|];
};

let create_observe_option_max_age seconds => {
  let bits = [%bitstring {|seconds : 32 : bigendian|}];
  Bitstring.string_of_bitstring bits
};

let create_max_age seconds => {
  let bits = [%bitstring {|seconds : 32 : bigendian|}];
  Bitstring.string_of_bitstring bits
};

let create_observe_options ::format=json_format age::age uri::uri => {
  let uri_path = create_option number::11 value::uri;
  let uri_host = create_option number::3 value::(Unix.gethostname ());
  let content_format = create_option number::12 value::format;
  let observe = create_option number::6 value::"";
  let max_age = create_option number::14 value::(create_max_age (Int32.of_int age));
  create_options [|uri_path, uri_host, observe, content_format, max_age|];
};


let set_main_socket_security soc key => {
  ZMQ.Socket.set_curve_serverkey soc key;
  let (curve_public_key, curve_private_key) = ZMQ.Curve.keypair ();
  ZMQ.Socket.set_curve_publickey soc curve_public_key;
  ZMQ.Socket.set_curve_secretkey soc curve_private_key;
};

let set_dealer_socket_security soc key => {
  ZMQ.Socket.set_curve_serverkey soc key;
  let (router_public_key, router_private_key) = ZMQ.Curve.keypair ();
  ZMQ.Socket.set_curve_publickey soc router_public_key;
  ZMQ.Socket.set_curve_secretkey soc router_private_key;
};

let connect_request_socket ctx endpoint server_key => {
  let soc = ZMQ.Socket.create ctx ZMQ.Socket.req;
  set_main_socket_security soc server_key;
  ZMQ.Socket.connect soc endpoint;
  Lwt_zmq.Socket.of_socket soc;
};

let connect_dealer_socket ctx endpoint server_key ident => {
  let soc = ZMQ.Socket.create ctx ZMQ.Socket.dealer;
  set_dealer_socket_security soc server_key;
  ZMQ.Socket.set_identity soc ident;
  ZMQ.Socket.connect soc endpoint;
  Lwt_zmq.Socket.of_socket soc;
};

let close_socket lwt_soc => {
  let soc = Lwt_zmq.Socket.to_socket lwt_soc;
  ZMQ.Socket.close soc;
};



let get_req ::token=? ::format=json_format uri::uri () => {
  let (tkl, tk) = switch token { | None => (0, "") | Some token => (String.length token, token)};
  let (options_value, options_length, options_count) = create_get_options uri::uri format::format;
  let (header_value, header_length) = create_header ::tkl oc::options_count code::1;
  let (token_value, token_length) = create_token ::tk;
  let bits = [%bitstring
    {|header_value : header_length : bitstring;
      token_value : token_length : string;
      options_value : options_length : bitstring
    |}
  ];
  Bitstring.string_of_bitstring bits;
};

let get t ::token=? ::format=json_format ::uri () => {
  Lwt_log_core.debug_f "GETing: %s" uri >>= fun () => {
    let req_msg = get_req ::?token ::format ::uri ();
    send_request msg::req_msg to::t.request_socket >>= fun resp =>
    switch resp {
    | Response.Payload payload => Lwt.return payload;
    | _ => Lwt.fail (Failure (string_of_response resp));
    };
  };
};

let post_req ::token=? ::format=json_format uri::uri payload::payload () => {
  let (tkl, tk) = switch token { | None => (0, "") | Some token => (String.length token, token)};
  let (options_value, options_length, options_count) = create_post_options uri::uri format::format;
  let (header_value, header_length) = create_header ::tkl oc::options_count code::2;
  let (token_value, token_length) = create_token ::tk;
  let payload_length = String.length payload * 8;
  let bits = [%bitstring
    {|header_value : header_length : bitstring;
      token_value : token_length : string;
      options_value : options_length : bitstring;
      payload : payload_length : string
    |}
  ];
  Bitstring.string_of_bitstring bits;
};

let post t ::token=? ::format=json_format ::uri ::payload () => {
  Lwt_log_core.debug_f "POSTing: %s, with\n%s" uri payload >>= fun () => {
    let req_msg = post_req ::?token ::format ::uri ::payload ();
    send_request msg::req_msg to::t.request_socket >>= fun resp =>
    switch resp {
    | Response.OK => Lwt.return_unit;
    | _ => Lwt.fail (Failure (string_of_response resp));
    };
  };
};

let observe_req ::token=? ::format=json_format uri::uri ::age=? () => {
  let (tkl, tk) = switch token { | None => (0, "") | Some token => (String.length token, token)};
  let age = switch age { | None => 0 | Some age => age };
  let (options_value, options_length, options_count) = create_observe_options age::age uri::uri format::format;
  let (header_value, header_length) = create_header ::tkl oc::options_count code::1;
  let (token_value, token_length) = create_token ::tk;
  let bits = [%bitstring
    {|header_value : header_length : bitstring;
      token_value : token_length : string;
      options_value : options_length : bitstring
    |}
  ];
  Bitstring.string_of_bitstring bits;
};


let observe t ::token=? ::format=json_format ::uri ::age=0 () => {
  Lwt_log_core.debug_f "Observing: %s for %d seconds" uri age >>= fun () => {
    let req_msg = observe_req ::?token ::format ::uri ::age ();
    send_request msg::req_msg to::t.request_socket >>= fun resp =>
    switch resp {
    | Observe key ident =>
        let deal_soc = connect_dealer_socket t.zmq_ctx t.dealer_endpoint key ident;
        t.observers = [(uri, deal_soc), ...t.observers];
        let pump_data () =>
          Lwt_zmq.Socket.recv deal_soc >>= fun msg =>
          handle_response ::msg >>= fun resp =>
          switch resp {
          | Response.Payload p => Lwt.return (Some p);
          | _ =>
              close_socket deal_soc;
              Lwt_log_core.warning_f "%s" (string_of_response resp) >>= fun () =>
              Lwt.return None;
          };
        Lwt.return @@ Lwt_stream.from pump_data;
    | _ => Lwt.fail (Failure (string_of_response resp));
    };
  };
};

let stop_observing t ::uri => {
  if (List.mem_assoc uri t.observers) {
    let soc = List.assoc uri t.observers;
    close_socket soc;
    t.observers = List.remove_assoc uri t.observers;
    Lwt.return_unit;
  } else {
    Lwt.return_unit;
  };
};

/*
let post_loop socket count => {
  let rec loop n => {
    send_request msg::(post uri::!uri_path payload::!payload ()) to::socket >>=
      fun resp =>
        switch resp {
        | Response.OK => {
            Lwt_io.printf "=> Created\n" >>=
              fun () =>
                if (n > 1) {
                  Lwt_unix.sleep !call_freq >>= fun () => loop (n - 1);
                } else {
                  Lwt.return_unit;
                };
          };
        | Response.Error msg => Lwt_io.printf "=> %s\n" msg;
        | _ => failwith "unhandled response";
        };
  };
  loop count;
};


let get_loop socket count => {
  let rec loop n => {
    send_request msg::(get uri::!uri_path ()) to::socket >>=
      fun resp =>
        switch resp {
        | Response.Payload msg => {
            Lwt_io.printf "%s\n" msg >>=
              fun () =>
                if (n > 1) {
                  Lwt_unix.sleep !call_freq >>= fun () => loop (n - 1);
                } else {
                  Lwt.return_unit;
                };
          };
        | Response.Error msg => Lwt_io.printf "=> %s\n" msg;
        | _ => failwith "unhandled response";
        };

  };
  loop count;
};


let observe_loop socket count => {
  let rec loop () => {
    Lwt_zmq.Socket.recv socket >>=
      handle_response >>=
        fun resp =>
          switch resp {
          | Response.Payload msg =>
              Lwt_io.printf "%s\n" msg >>=
                fun () => loop ();
          | Response.Unavailable =>
              Lwt.return_unit;
          | _ => failwith "unhandled response";
          };
  };
  loop ();
};



let observe_test ctx => {
  let req_soc = connect_request_socket !req_endpoint ctx ZMQ.Socket.req;
  Lwt_log_core.debug_f "Subscribing:%s" !uri_path >>=
    fun () =>
      send_request msg::(observe uri::!uri_path ()) to::req_soc >>=
        fun resp =>
          switch resp {
          | Response.Observe key ident => {
              Lwt_log_core.debug_f "Observing:%s with ident:%s" !uri_path ident >>=
                fun () => {
                  close_socket req_soc;
                  let deal_soc = connect_dealer_socket key ident !deal_endpoint ctx ZMQ.Socket.dealer;
                  observe_loop deal_soc !loop_count >>=
                    fun () => close_socket deal_soc |> Lwt.return;
                };
            };
          | Response.Error msg => Lwt_io.printf "=> %s\n" msg;
          | _ => failwith "unhandled response";
          };

};

let handle_format format => {
  let id = switch format {
  | "text" => 0;
  | "json" => 50;
  | "binary" => 42;
  | _ => raise (Arg.Bad "Unsupported format");
  };
  content_format := create_content_format id;
};


let parse_cmdline () => {
  let usage = "usage: " ^ Sys.argv.(0);
  let speclist = [
    ("--request-endpoint", Arg.Set_string req_endpoint, ": to set the request/reply endpoint"),
    ("--router-endpoint", Arg.Set_string deal_endpoint, ": to set the router/dealer endpoint"),
    ("--server-key", Arg.Set_string curve_server_key, ": to set the curve server key"),
    ("--public-key", Arg.Set_string curve_public_key, ": to set the curve public key"),
    ("--secret-key", Arg.Set_string curve_secret_key, ": to set the curve secret key"),
    ("--token", Arg.Set_string token, ": to set access token"),
    ("--path", Arg.Set_string uri_path, ": to set the uri path"),
    ("--payload", Arg.Set_string payload, ": to set the message payload"),
    ("--format", Arg.Symbol ["text", "json", "binary"] handle_format, ": to set the message content type"),
    ("--loop", Arg.Set_int loop_count, ": to set the number of times to run post/get/observe test"),
    ("--freq", Arg.Set_float call_freq, ": to set the number of seconds to wait between each get/post operation"),
    ("--mode", Arg.Symbol ["post", "get", "observe"] handle_mode, " : to set the mode of operation"),
    ("--file", Arg.Set file, ": payload contents comes from a file"),
    ("--max-age", Arg.Set_int max_age, ": time in seconds to observe a path"),
    ("--enable-logging", Arg.Set log_mode, ": turn debug mode on"),
  ];
  Arg.parse speclist (fun err => raise (Arg.Bad ("Bad argument : " ^ err))) usage;
};
*/

/* server_key: qDq63cJF5gd3Jed:/3t[F8u(ETeep(qk+%pmj(s? */
/* public_key: MP9pZzG25M2$.a%[DwU$OQ#-:C}Aq)3w*<AY^%V{ */
/* secret_key: j#3yqGG17QNTe(g@jJt6[LOg%ivqr<:}L%&NAUPt */


let report_error e => {
  let msg = Printexc.to_string e;
  let stack = Printexc.get_backtrace ();
  let _ = Lwt_log_core.error_f "Opps: %s%s" msg stack;
};


let create_client ::endpoint ::dealer_endpoint ::server_key ::logging=false () => {
  let zmq_ctx = ZMQ.Context.create ();
  let request_socket = connect_request_socket zmq_ctx endpoint server_key;
  let observers = [];
  let client = {zmq_ctx, endpoint, dealer_endpoint, request_socket, observers};
  if (logging) { setup_logger (); };
  client
};
