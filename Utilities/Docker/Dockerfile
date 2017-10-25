# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

FROM ubuntu:16.04
# Install related packages.
RUN apt-get -q update && \
    apt-get -q install -y \
    build-essential \
    make \
    libc6-dev \
    clang-3.6 \
    curl \
    libedit-dev \
    python2.7 \
    python2.7-dev \
    libicu-dev \
    rsync \
    libxml2 \
    git \
    libcurl4-openssl-dev \
    vim \
    libblocksruntime-dev \
    && update-alternatives --quiet --install /usr/bin/clang clang /usr/bin/clang-3.6 100 \
    && update-alternatives --quiet --install /usr/bin/clang++ clang++ /usr/bin/clang++-3.6 100 \
    && rm -r /var/lib/apt/lists/*
ARG SNAPSHOT

COPY $SNAPSHOT /
RUN tar -xvzf $SNAPSHOT --directory / --strip-components=1 && \
    rm -rf swift-DEVELOPMENT-SNAPSHOT*
# Set Swift Path
ENV PATH /usr/bin:$PATH
# Print Installed Swift Version
RUN swift --version
