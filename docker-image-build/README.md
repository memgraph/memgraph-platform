# Scripts for creating custom docker images

Each folder contains `.sh` script for creating either docker image or memgraph debian. Before running scripts, you need to change permissions on `create_` scripts with command:

```
sudo chmod 777 create_deb.sh
```

## Creating Memgraph debian 11 package

To create Memgraph `.deb` file do the following steps:

1. Position yourself in `memgraph_deb` folder.
2. Run script `create_db.sh` with following command you can create deb from github repository:

    ```console
    $ sudo bash ./create_deb.sh {branch_name} {deb_name}
    ```
   - `{branch_name}` - use any of the branches from `memgraph` repository, i.e. `master`, `T1220-MG-properties-c++-api-bug`, and so on for script to pull and build `memgraph` from it
   -   `{deb_name}` determines middle part of final package file.  `.deb` package file name is constructed as follows: `memgraph-{deb_name}_amd64.deb`


Script stores all `.deb` files inside folder `output_debian`.

## Creating MAGE Docker image

This script releases docker image **only** for platform `amd64/linux` arhitectures. 

1. Position yourself in `mage_img` folder. 

2. Store memgraph debian package file in `memgraph_deb_files` folder with exact following name `memgraph-{deb_name}.deb` and run script with following command:

    ```
    ./create_mage_img.sh {path_to_mage|branch_name} {image_name} {deb_name}
    ```
    - `{path_to_mage|branch_name}` 
    - to build from **local repository**, set first argument to path to MAGE repository, i.e `/home/memgraph/mage/`
    - to build from MAGE branch, set first argument to branch name, i.e `main`
    - `{deb_name}` - deb package file name 
    - `{image_name}` - determines final image name

3. Docker image will be stored in folder `output` in `tar.gz` format, for example `{image_name}.tar.gz`. To check how to load image, jump to Loading custom docker image section.


## Creating Platform Docker image

> ### Note: Lab is a private repo so this build is unavailable to public. You can still build Memgraph + MAGE above and use downloaded Lab with your image.

Position yourself in `platform` folder, make sure you added memgraph debian in `memgraph_deb_files`, configured `ssh` correctly to connect to `github` and run script with following command if you want to build image from local repository:

```
./create_platform_img.sh .../platform image_name deb_package_name github_pat_token

```

or with command if you want to create image from github repository:

```
./create_platform_img.sh main image_name deb_package_name github_pat_token

```

Platform docker image can be also built with only memgraph and lab wihout mage.  run script with following command if you want to build image from local repository:

```
./create_platform_img.sh .../platform image_name deb_package_name github_pat_token true

```

or with command if you want to create image from github repository:

```
./create_platform_img.sh main image_name deb_package_name github_pat_token true

```

Docker image will be stored in folder `output` in `tar.gz` format, for example `image_name.tar.gz`. Docker image is released for platform `amd64/linux` arhitectures.


**NOTE** Deb packages need to be stored in format `memgraph-deb_package_name.deb`, for example `memgraph-master_amd64.deb` and you start script with `master_amd64`.


## Loading custom docker image

Docker image can be loaded with (it takes some time):

```
docker load < image_name.tar.gz
```

and then used for example like this:

```
docker run -it --rm -p 7687:7687 --name mage image_name
```
