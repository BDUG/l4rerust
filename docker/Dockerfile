FROM ubuntu:22.04

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        bison \
        build-essential \
        cpanminus \
        curl \
        device-tree-compiler \
        dialog \
        doxygen \
        e2fsprogs \
        flex \
        gawk \
        gcc-aarch64-linux-gnu \
        gcc-arm-linux-gnueabihf \
        git \
        graphviz \
        libgit-repository-perl \
        libncurses-dev \
        liburi-perl \
        libxml-parser-perl \
        meson \
        mtools \
        ninja-build \
        openssh-client \
        perl \
        pkg-config \
        python3 \
        qemu \
        qemu-system \
        wget \
        xorriso \
    && cpanm --notest Git::Repository \
    && rm -rf /var/lib/apt/lists/*

# Install ham build tool
RUN curl -L https://raw.githubusercontent.com/kernkonzept/ham/master/ham -o /usr/local/bin/ham \
    && chmod +x /usr/local/bin/ham

ENV CROSS_COMPILE_ARM=arm-linux-gnueabihf-
ENV CROSS_COMPILE_ARM64=aarch64-linux-gnu-

WORKDIR /workspace
COPY scripts/ /workspace/scripts/

ENTRYPOINT ["/workspace/scripts/build.sh"]
