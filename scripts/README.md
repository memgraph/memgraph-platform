# Scripts for creating custom memgraph packages and docker images

* `build_memgraph.sh` -> by default builds memgraph under `mage/cpp/memgraph`
* `debian_pack.sh`    -> builds memgraph debian package under the `memgraph-builder` container
* `pack_mage.sh`      -> creates docker image based on the mage Dockerfile
* `pack_platform.sh`  -> creates platform docker images (full OR without mage)

Run `{script}.sh -h` to figure out how to start building.

## Notes

* Lab is a private repo so this build is unavailable to public
  (`pack_platform.sh`). You can still build Memgraph + MAGE above and use
  downloaded Lab with your image.
* Docker image is released for platform `amd64/linux` arhitectures only.

## Loading custom docker image

Docker image can be loaded with (it takes some time):
```
docker load < <IMAGE_NAME>.tar.gz
```
and then used for example like this:
```
docker run -it --rm -p 7687:7687 --name <NAME> <IMAGE_NAME>
```
