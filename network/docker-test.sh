#!/bin/bash
# execute smoke test using docker-compose

docker exec -it cli bash -c 'cd artifacts && ./test-sample.sh'
