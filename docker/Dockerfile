FROM ubuntu:22.04

RUN dpkg --add-architecture armhf \
    && dpkg --add-architecture arm64 \
    && apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        bison \
        build-essential \
        cmake \
        cpanminus \
        curl \
        device-tree-compiler \
        dialog \
        doxygen \
        e2fsprogs \
        flex \
        gawk \
        g++-aarch64-linux-gnu \
        g++-arm-linux-gnueabihf \
        git \
        graphviz \
        libxcrypt-dev:arm64 \
        libxcrypt-dev:armhf \
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
COPY scripts/l4re.config /workspace/.config
RUN chown root:root /workspace/.config && chmod 644 /workspace/.config

ENTRYPOINT ["/workspace/scripts/build.sh"]
