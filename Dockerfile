FROM ocaml/opam:alpine-3.6_ocaml-4.04.2

WORKDIR /lib-ml-databox
ADD . .

RUN sudo apk update && sudo apk add m4 bash gmp-dev perl zeromq-dev
#for the fix:https://github.com/mirage/ocaml-conduit/pull/234
#could be deleted once the newest versions are in OPAM docker image
RUN opam pin add -n conduit-lwt-unix.1.0.3 git://github.com/mirage/ocaml-conduit#v1.0.3
RUN opam pin add lib-databox.0.0.1 .
