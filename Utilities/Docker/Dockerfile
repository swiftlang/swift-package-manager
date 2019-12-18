# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

FROM ubuntu:18.04

# Install related packages.
RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true && \
    apt-get -q update && \
    apt-get -q install -y \
        make \
        libc6-dev \
        clang-3.9 \
        curl \
        libedit-dev \
        libpython2.7 \
        libicu-dev \
        libssl-dev \
        libxml2 \
        tzdata \
        git \
        libcurl4-openssl-dev \
        ninja-build \
        sqlite3 \
        libsqlite3-dev \
        libncurses5-dev \
        pkg-config \
        apt-transport-https \
        ca-certificates \
        gnupg \
        wget \
        zip \
        unzip \
        software-properties-common && \
    wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | apt-key add - && \
    apt-add-repository 'deb https://apt.kitware.com/ubuntu/ bionic main' && \
    apt-get -q update && \
    apt-get -q install -y cmake && \
    update-alternatives --quiet --install /usr/bin/clang clang /usr/bin/clang-3.9 100 && \
    update-alternatives --quiet --install /usr/bin/clang++ clang++ /usr/bin/clang++-3.9 100 && \
    rm -r /var/lib/apt/lists/*

ARG SNAPSHOT
COPY $SNAPSHOT /
RUN tar -xvzf $SNAPSHOT --directory / --strip-components=1 && \
    rm -rf swift-DEVELOPMENT-SNAPSHOT*

# Set Swift Path
ENV PATH /usr/bin:$PATH

# Print Installed Swift Version
RUN swift --version
