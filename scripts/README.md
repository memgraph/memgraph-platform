# Scripts for creating custom docker images

Each folder contains `.sh` script for creating either docker image or memgraph debian. Before running scripts, you need to change permissions on `build_` scripts with command:

```
sudo chmod 777 <SCRIPT_NAME>
```

Additional note, always check before running any scripts if your local user has the permission to read and write over the `resources` directory, which gets created in the `scripts` directory.

## Creating Memgraph debian 11 package

To create a Memgraph `.deb` file do the following steps:

1. Run the `build_deb.sh` script as follows to create the deb from the GitHub repository:

    ```console
    $ sudo ./build_deb.sh {branch_name} {deb_name}
    ```
   - `{branch_name}`: any branch from the `memgraph` repo, e.g. `master` or `T1220-MG-properties-c++-api-bug`; for the script to pull and build `memgraph` from it
   - `{deb_name}`: used to name the final  `.deb` package file: `memgraph-{deb_name}_amd64.deb`


The script stores all `.deb` files in the `output_debian` folder.

## Creating MAGE Docker image

> ### This script releases docker images **only** for `amd64/linux` platform arhitectures. 

1. Store the memgraph Debian package file in the `memgraph_deb_files` folder with the exact name: `memgraph-{deb_name}_amd64.deb` and run the script with the following command:

    ```
    sudo ./build_mage_img.sh {branch_name} {image_name} {deb_name}
    ```
    - `{branch_name}` - branch name, e.g. `main`
    - `{deb_name}` - deb package filename 
    - `{image_name}` - for the final image name

3. The docker image will be stored in the `output` folder in the `tar.gz` format, e.g. `{image_name}.tar.gz`. To check how to load the image, jump to the [Loading custom docker image](#loading-custom-docker-image) section.


## Creating Platform Docker image

> ### Note: Lab is a private repo so this build is unavailable to public. You can still build Memgraph + MAGE above and use downloaded Lab with your image.

> ### Docker image is released for platform `amd64/linux` arhitectures only.

1. Make sure you added memgraph debian in `memgraph_deb_files`, configured `ssh` correctly to connect to `github` and run script with following command:
    ```
    ./build_platform_img.sh {branch_name} {image_name} {deb_name} {github_pat_token}

    ```
    - `{branch_name}` - branch name of memgraph-platform, e.g. `main`
    - `{image_name}` - name the final image name of memgraph platform
    - `{deb_name}` - middle name of the deb file you provided in previous steps, e.g. memgraph-{deb_name}_amd64.deb
    - `{github_pat_token}` - your github pat token for downloading Memgraph Lab


2. Platform docker image can be also built with only memgraph and lab wihout mage.  run script with following command:
    ```
    ./build_platform_img.sh main image_name deb_package_name github_pat_token true

    ```

Docker image will be stored in folder `output` in `tar.gz` format, for example `image_name.tar.gz`.


**NOTE** Deb packages need to be stored in format `memgraph-{deb_name}_amd64.deb`, for example `memgraph-feature_amd64.deb` and you start script with `feature`.

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
docker load < <IMAGE_NAME>.tar.gz
```

and then used for example like this:

```
docker run -it --rm -p 7687:7687 --name <NAME> <IMAGE_NAME>
```
```
docker load -i <IMAGE_NAME>.tar.gz
```
and then used for example like this:
```
docker run -it --rm -p 7687:7687 --name <NAME> <IMAGE_NAME>
```
Platform image has a specific run command, please refer to the root of this repo.
