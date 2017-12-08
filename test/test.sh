#!/bin/bash

docker rm --force zest >/dev/null 2>&1
docker run -p 5555:5555 -p 5556:5556 -d --name zest --rm jptmoore/zest /app/zest/server.exe --secret-key-file example-server-key --enable-logging
./test.exe

if [ ${?} != 0 ]; then
    echo -e "\n>>>>>>>>>> zest server logs >>>>>>>>>>"
    docker logs zest
fi
