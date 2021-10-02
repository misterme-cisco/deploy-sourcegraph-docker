#!/usr/bin/env bash
set -e
source ./replicas.sh

# Description: Backend for indexed text search operations.
#
# Disk: 200GB / persistent SSD
# Network: 100mbps
# Liveness probe: HTTP GET http://zoekt-webserver-$1:6070/healthz
# Ports exposed to other Sourcegraph services: 6070/TCP
# Ports exposed to the public internet: none
#
VOLUME="$HOME/sourcegraph-docker/zoekt-$1-shared-disk"
./ensure-volume.sh $VOLUME 100
docker run --detach \
    --name=zoekt-webserver-$1 \
    --hostname=zoekt-webserver-$1 \
    --network=sourcegraph \
    --restart=always \
    --cpus=16 \
    --memory=100g \
    -e GOMAXPROCS=16 \
    -e HOSTNAME=zoekt-webserver-$1:6070 \
    -v $VOLUME:/data/index \
<<<<<<< HEAD
    index.docker.io/sourcegraph/indexed-searcher:3.27.4@sha256:696a4f67648f8ba31afac10c0d2de50e4aed1879db0aa6078e55091ac27ba744
=======
    index.docker.io/sourcegraph/indexed-searcher:3.28.0@sha256:d623877defd1551363b840aa132789239e0c3e89d080ee7c777eebdd2c3627ec
>>>>>>> 3.28

echo "Deployed zoekt-webserver $1 service"
