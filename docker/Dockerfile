FROM ubuntu:22.04

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        build-essential \
        gcc-arm-linux-gnueabihf \
        gcc-aarch64-linux-gnu \
        qemu \
        e2fsprogs \
        meson \
        ninja-build \
        pkg-config \
        git \
        curl \
        python3 \
        openssh-client \
        perl \
        cpanminus \
        libgit-repository-perl \
    && cpanm --notest Git::Repository \
    && rm -rf /var/lib/apt/lists/*

ENV CROSS_COMPILE_ARM=arm-linux-gnueabihf-
ENV CROSS_COMPILE_ARM64=aarch64-linux-gnu-

WORKDIR /workspace
COPY scripts/ /workspace/scripts/

ENTRYPOINT ["/workspace/scripts/build.sh"]
