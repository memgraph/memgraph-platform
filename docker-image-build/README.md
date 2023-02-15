# Scripts for creating custom docker images

Each folder contains `.sh` script for creating either docker image or memgraph debian. Before running scripts, you need to change permissions on `create_` scripts with command:

```
sudo chmod 777 create_deb.sh
```

## Creating Memgraph debian 11 package

To create a Memgraph `.deb` file do the following steps:

1. Position yourself in `memgraph_deb` folder.
2. Run the `create_db.sh` script as follows to create the deb from the GitHub repository:

    ```console
    $ sudo bash ./create_deb.sh {branch_name} {deb_name}
    ```
   - `{branch_name}`: any branch from the `memgraph` repo, e.g. `master` or `T1220-MG-properties-c++-api-bug`; for the script to pull and build `memgraph` from it
   -   `{deb_name}`: used to name the final  `.deb` package file: `memgraph-{deb_name}_amd64.deb`


The script stores all `.deb` files in the `output_debian` folder.

## Creating MAGE Docker image

This script releases docker images **only** for `amd64/linux` platform arhitectures. 

1. Position yourself in the `mage_img` folder. 

2. Store the memgraph Debian package file in the `memgraph_deb_files` folder with the exact name: `memgraph-{deb_name}.deb` and run the script with the following command:

    ```
    ./create_mage_img.sh {path_to_mage|branch_name} {image_name} {deb_name}
    ```
    - `{path_to_mage|branch_name}` 
    - to build from a **local repository**, set the first argument to the path to the MAGE repository, i.e `/home/memgraph/mage/`
    - to build from a MAGE branch, set the first argument to the branch name, e.g. `main`
    - `{deb_name}` - deb package filename 
    - `{image_name}` - for the final image name

3. The docker image will be stored in the `output` folder in the `tar.gz` format, e.g. `{image_name}.tar.gz`. To check how to load the image, jump to the [Loading custom docker image](#loading-custom-docker-image) section.


## Creating Platform Docker image

> ### Note: Lab is a private repo so this build is unavailable to public. You can still build Memgraph + MAGE above and use downloaded Lab with your image.

Position yourself in `platform_img` folder, make sure you added memgraph debian in `memgraph_deb_files`, configured `ssh` correctly to connect to `github` and run script with following command if you want to build image from local repository:

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
