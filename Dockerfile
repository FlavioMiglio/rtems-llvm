FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        g++ \
        gdb \
        unzip \
        pax \
        bison \
        flex \
        texinfo \
        python3-dev \
        python-is-python3 \
        libncurses-dev \
        zlib1g-dev \
        ninja-build \
        pkg-config \
        git \
        ca-certificates \
        cmake \
        qemu-system-arm \
        stlink-tools \
        picocom \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/rtems-llvm

CMD ["/bin/bash"]
