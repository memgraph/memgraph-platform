CURR_DIR="$PWD"
MEMGRAPH_DIR="$CURR_DIR/memgraph"
cloned=true
branch_name=$1
deb_name=$2
mkdir -p output_debian
git clone -b $branch_name https://github.com/memgraph/memgraph.git

docker pull memgraph/memgraph-builder
docker run --name meme-build -itd -v $MEMGRAPH_DIR:/memgraph -v $CURR_DIR/output:/memgraph/build/output --entrypoint bash memgraph/memgraph-builder 
docker exec -i meme-build bash < $CURR_DIR/build.sh
docker stop meme-build
docker rm meme-build
find $CURR_DIR/output -type f -name "*.deb" -exec mv -f {} output_debian/memgraph-${deb_name}_amd64.deb \;

if $cloned;then
  rm -rf $MEMGRAPH_DIR
fi
rm -rf $CURR_DIR/output

