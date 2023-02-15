CURR_DIR="$PWD"
MAGE_DIR="$CURR_DIR/mage"
cloned=true
branch_or_dir=$1
image_name=$2
deb_name=$3

mkdir -p output

if [ -d "$branch_or_dir" ]
  then
    MAGE_DIR=$branch_or_dir
    cloned=false
  else
    git clone --recurse-submodules -b $1 https://github.com/memgraph/mage.git
fi

cp "$CURR_DIR/memgraph_deb_files/memgraph-$deb_name.deb" "$MAGE_DIR/memgraph-$deb_name.deb"
cd $MAGE_DIR
docker buildx build --platform=linux/amd64 -t $image_name --build-arg TARGETARCH=$deb_name -f $MAGE_DIR/Dockerfile.release .
cd $CURR_DIR

docker save $image_name | gzip -f > "$CURR_DIR/output/$image_name.tar.gz"
docker rmi $image_name

rm -rf $image_name
if $cloned;then
  rm -rf $MAGE_DIR
fi
