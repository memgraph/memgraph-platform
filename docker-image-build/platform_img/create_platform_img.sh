CURR_DIR="$PWD"
PLATFORM_DIR="$CURR_DIR/memgraph-platform"
cloned=true
dir_or_branch=$1
image_name=$2
target_arch=$3
token=$4
memgraph_and_lab=${5-false}

mkdir -p output

if [ -d "dir_or_branch" ]
  then
    PLATFORM_DIR=dir_or_branch
    cloned=false
  else
    git clone --recurse-submodules -b $1 git@github.com:memgraph/memgraph-platform.git
fi

cp "$CURR_DIR/memgraph_deb_files/memgraph-$target_arch.deb" "$PLATFORM_DIR/memgraph-$target_arch.deb"
cd $PLATFORM_DIR

if [ "$memgraph_and_lab" == true ];
then
    docker buildx build --platform=linux/amd64 -t $image_name --build-arg TARGETARCH=$target_arch --build-arg NPM_PACKAGE_TOKEN=$token -f $PLATFORM_DIR/memgraph_and_lab.Dockerfile .
else
    docker buildx build --platform=linux/amd64 -t $image_name --build-arg TARGETARCH=$target_arch --build-arg NPM_PACKAGE_TOKEN=$token -f $PLATFORM_DIR/Dockerfile .

fi
cd $CURR_DIR
docker save $image_name | gzip -f > "$CURR_DIR/output/$image_name.tar.gz"
docker rmi $image_name
rm -rf $image_name
if $cloned;then
  rm -rf $PLATFORM_DIR
fi
