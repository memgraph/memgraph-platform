#!/bin/bash

CURR_DIR="$PWD"
PLATFORM_DIR="${CURR_DIR}/memgraph-platform"

branch=$1
image_name=$2
target_arch=$3
token=$4
memgraph_and_lab=${5-false}

git clone --recurse-submodules -b $1 https://github.com/memgraph/memgraph-platform.git

cp "${CURR_DIR}/resources/memgraph-${target_arch}_amd64.deb" "${PLATFORM_DIR}/memgraph-${target_arch}_amd64.deb"
cd ${PLATFORM_DIR}

dockerfile=${PLATFORM_DIR}/Dockerfile

if [ "${memgraph_and_lab}" == true ];
then
    dockerfile = ${PLATFORM_DIR}/memgraph_and_lab.Dockerfile
fi

docker buildx build --platform=linux/amd64 -t ${image_name} --build-arg TARGETARCH=${target_arch}_amd64 --build-arg NPM_PACKAGE_TOKEN=${token} -f ${dockerfile} .

cd ${CURR_DIR}

docker save ${image_name} | gzip -f > "${CURR_DIR}/resources/${image_name}.tar.gz"
docker rmi ${image_name}

rm -rf ${image_name}
rm -rf ${PLATFORM_DIR}
