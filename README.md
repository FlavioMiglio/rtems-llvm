# rtems-llvm

#### Flavio Migliorati, Giorgio Barocco, Francesco Bazzano

## Submodule initialization and download

After cloning the repo, initialize and download the two submodules (`rtems` and `rtems-rsb`):

    git submodule init
    git submodule update

## Install build dependencies

Install the dependencies required by the RSB by following [this guide](https://docs.rtems.org/docs/main/user/hosts/index.html)

## Choosing an Installation Prefix

First you have to choose a prefix, which will also be the prefix used for the RTEMS toolchain, so follow the guidance [here](https://docs.rtems.org/docs/main/user/start/prefixes.html) to select an appropriate prefix.

Ideally, the prefix should be chosen such that it points to the `7` folder in this repository. Otherwise, copy the content of the folder in your prefix.

In the following commands we will use the prefix `$HOME/rtems-llvm/7` as an example.

## Building the toolchain with RSB

    ./build-toolchain.sh --prefix "$HOME/rtems-llvm/7" --gcc-bset 7/rtems-aarch64

## Building the BSP

    ./build-bsp.sh --prefix "$HOME/rtems-llvm/7" --bsp aarch64/a72_lp64_qemu

