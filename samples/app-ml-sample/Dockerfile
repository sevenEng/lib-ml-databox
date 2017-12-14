FROM lib-ml-databox:latest as BUILDER

WORKDIR /app-builder
ADD . .

RUN sudo chown opam: -R . && opam config exec -- jbuilder build src/main.exe

FROM alpine:3.6

LABEL databox.type="app"

WORKDIR /app-ml-sample
RUN apk update && apk add zeromq-dev gmp-dev
COPY --from=BUILDER /app-builder/_build/default/src/main.exe app
COPY --from=BUILDER /app-builder/src/www www

EXPOSE 8080

ENTRYPOINT [ "./app" ]
