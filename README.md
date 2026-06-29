# rtems-llvm

#### Flavio Migliorati, Giorgio Barocco, Francesco Bazzano

## Submodule initialization and download

After cloning the repo, initialize and download the two submodules (`rtems` and `rtems-rsb`):

    git submodule init
    git submodule update

## Start the container

    podman compose up -d
    podman compose exec rtems-llvm /bin/bash

All subsequent commands are run inside the container. The working directory is `/opt/rtems-llvm`.

## Build the toolchain

The toolchain is built in two steps using the RTEMS Source Builder (RSB): first the ARM GCC cross-compiler, then the LLVM/Clang toolchain. The prefix `/opt/rtems-llvm/rtems` is already set up inside the container.

    cd src/rtems-rsb/rtems

    ../source-builder/sb-set-builder --prefix=/opt/rtems-llvm/rtems 7/rtems-arm

    chmod -R u+w /opt/rtems-llvm/rtems

    ../source-builder/sb-set-builder --prefix=/opt/rtems-llvm/rtems 7/rtems-llvm

## Build the BSP (STM32F4)

    cd /opt/rtems-llvm/src/rtems

    echo "[arm/stm32f4]" > config.ini
    echo "BUILD_TESTS = True" >> config.ini

    ./waf configure --prefix=/opt/rtems-llvm/rtems

    ./waf

    ./waf install
