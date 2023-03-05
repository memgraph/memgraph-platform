#!/bin/bash

CURR_DIR="$PWD"
MAGE_DIR="$CURR_DIR/mage"

branch=$1
image_name=$2
deb_name=$3

git clone --recurse-submodules -b $1 https://github.com/memgraph/mage.git

cp "${CURR_DIR}/resources/memgraph-${deb_name}_amd64.deb" "${MAGE_DIR}/memgraph-${deb_name}_amd64.deb"

cd ${MAGE_DIR}

docker buildx build --target prod --platform=linux/amd64 -t ${image_name} --build-arg TARGETARCH=${deb_name}_amd64 -f ${MAGE_DIR}/Dockerfile.release .

cd ${CURR_DIR}

docker save ${image_name} | gzip -f > "${CURR_DIR}/resources/${image_name}.tar.gz"
docker rmi ${image_name}

rm -rf ${image_name}
rm -rf ${MAGE_DIR}
