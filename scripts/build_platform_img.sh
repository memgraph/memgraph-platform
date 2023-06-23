#!/bin/bash

# TODO: Rename to build_platform.sh
# TODO: Here only the Memgraph package is required as an impor
# TODO: Add scripts under Docker ignore

CURR_DIR="$PWD"
PLATFORM_DIR="${CURR_DIR}/memgraph-platform"
# TODO: branch is not used at all
branch=$1
image_name=$2
# memgraph-${target_arch}_amd64.deb
target_arch=$3
# TODO: Npm package toker -> for lab
token=$4
# TODO: An option build wihout mage
memgraph_and_lab=${5-false}

# TODO: but we already have this here (the whole repo)?
git clone --recurse-submodules -b $1 https://github.com/memgraph/memgraph-platform.git
cp "${CURR_DIR}/resources/memgraph-${target_arch}_amd64.deb" "${PLATFORM_DIR}/memgraph-${target_arch}_amd64.deb"
cd ${PLATFORM_DIR}
dockerfile=${PLATFORM_DIR}/Dockerfile
if [ "${memgraph_and_lab}" == true ];
then
    dockerfile = ${PLATFORM_DIR}/memgraph_and_lab.Dockerfile
fi

# NOTE: Command from the mage part....
# docker buildx build --target prod --platform=linux/amd64 -t ${image_name} --build-arg TARGETARCH=${deb_name}_amd64 -f ${MAGE_DIR}/Dockerfile.release .
docker buildx build --platform=linux/amd64 -t ${image_name} \
  --build-arg TARGETARCH=${target_arch}_amd64 --build-arg NPM_PACKAGE_TOKEN=${token} -f ${dockerfile} .

cd ${CURR_DIR}
docker save ${image_name} | gzip -f > "${CURR_DIR}/resources/${image_name}.tar.gz"
docker rmi ${image_name}
rm -rf ${image_name}
rm -rf ${PLATFORM_DIR}
