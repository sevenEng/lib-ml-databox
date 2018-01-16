FROM lib-ml-databox:latest as BUILDER

WORKDIR /driver-builder
ADD . .

RUN sudo chown opam: -R . && opam config exec -- jbuilder build src/main.exe

FROM alpine:3.6

LABEL databox.type="driver"

WORKDIR /driver-ml-sample
RUN apk update && apk add zeromq-dev gmp-dev
COPY --from=BUILDER /driver-builder/_build/default/src/main.exe driver

ENV OCAMLRUNPARAM=b

ENTRYPOINT [ "./driver" ]
