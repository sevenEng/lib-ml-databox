#!/bin/bash

docker rm --force zest >/dev/null 2>&1
docker run -p 5555:5555 -p 5556:5556 -d --name zest --rm jptmoore/zest:latest /app/zest/server.exe --secret-key-file example-server-key --enable-logging
./test.exe

docker logs zest >zest_log
echo -e "\n>>>>>>>>>>  zest server logs in ./zest_log  >>>>>>>>>>"
