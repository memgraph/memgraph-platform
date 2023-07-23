# Scripts for creating custom memgraph packages and docker images

Run `{script}.sh -h` to figure the details and how to start building.

## Notes

* If you need builder image for any supported operating system, please take a
  look under `memgraph/release/package/run.sh`. Under the
  `memgraph/release/package/` there are Dockerfiles to build builder
  containers.
* Lab is a private repo so this build is unavailable to public
  (`docker_image_platform.sh`). You can still build Memgraph + MAGE and use
  downloaded Lab with your image.

## Loading custom docker image

Docker image can be loaded with (it takes some time):
```
docker load -i <IMAGE_NAME>.tar.gz
```
and then used for example like this:
```
docker run -it --rm -p 7687:7687 --name <NAME> <IMAGE_NAME>
```
Platform image has a specific run command, please refer to the root of this repo.
