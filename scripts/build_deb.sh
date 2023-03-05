#!/bin/bash

CURR_DIR="$PWD"
MEMGRAPH_DIR="$CURR_DIR/memgraph"

cloned=true
branch_name=$1
deb_name=$2

git clone -b $branch_name https://github.com/memgraph/memgraph.git

mkdir -p resources

docker pull memgraph/memgraph-builder
docker stop meme-build || true && docker rm meme-build || true

docker run --name meme-build -itd -v $MEMGRAPH_DIR:/memgraph -v $CURR_DIR/resources/output:/memgraph/build/output --entrypoint bash memgraph/memgraph-builder 
docker exec -i meme-build bash < $CURR_DIR/_build_mg.sh
docker stop meme-build
docker rm meme-build

find $CURR_DIR/resources/output -type f -name "*.deb" -exec mv -f {} resources/memgraph-${deb_name}_amd64.deb \;

if $cloned;then
  rm -rf $MEMGRAPH_DIR
fi
rm -rf $CURR_DIR/resources/output

