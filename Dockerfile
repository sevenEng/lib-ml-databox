FROM ocaml/opam:alpine-3.6_ocaml-4.04.2

WORKDIR /lib-ml-databox
ADD . .

RUN sudo apk update && sudo apk add m4 bash gmp-dev perl zeromq-dev
RUN opam pin add lib-databox.0.0.1 .
