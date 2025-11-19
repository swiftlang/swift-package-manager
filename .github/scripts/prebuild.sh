#!/bin/bash
##===----------------------------------------------------------------------===##
##
## This source file is part of the Swift open source project
##
## Copyright (c) 2025 Apple Inc. and the Swift project authors
## Licensed under Apache License v2.0 with Runtime Library Exception
##
## See http://swift.org/LICENSE.txt for license information
## See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
##
##===----------------------------------------------------------------------===##

set -e

if [[ $(uname) == Darwin ]] ; then
    if [[ "$INSTALL_CMAKE" == "1" ]] ; then
        mkdir -p "$RUNNER_TOOL_CACHE"
        if ! command -v cmake >/dev/null 2>&1 ; then
            curl -fsSLO https://github.com/Kitware/CMake/releases/download/v4.1.2/cmake-4.1.2-macos-universal.tar.gz
            echo '3be85f5b999e327b1ac7d804cbc9acd767059e9f603c42ec2765f6ab68fbd367 cmake-4.1.2-macos-universal.tar.gz' > cmake-4.1.2-macos-universal.tar.gz.sha256
            sha256sum -c cmake-4.1.2-macos-universal.tar.gz.sha256
            tar -xf cmake-4.1.2-macos-universal.tar.gz
            ln -s "$PWD/cmake-4.1.2-macos-universal/CMake.app/Contents/bin/cmake" "$RUNNER_TOOL_CACHE/cmake"
        fi
        if ! command -v ninja >/dev/null 2>&1 ; then
            curl -fsSLO https://github.com/ninja-build/ninja/releases/download/v1.13.1/ninja-mac.zip
            echo 'da7797794153629aca5570ef7c813342d0be214ba84632af886856e8f0063dd9 ninja-mac.zip' > ninja-mac.zip.sha256
            sha256sum -c ninja-mac.zip.sha256
            unzip ninja-mac.zip
            rm -f ninja-mac.zip
            mv ninja "$RUNNER_TOOL_CACHE/ninja"
        fi
    fi
elif command -v apt-get >/dev/null 2>&1 ; then # bookworm, noble, jammy
    export DEBIAN_FRONTEND=noninteractive

    apt-get update -y

    # Build dependencies
    apt-get install -y libsqlite3-dev libncurses-dev

    # Debug symbols
    apt-get install -y libc6-dbg

    if [[ "$INSTALL_CMAKE" == "1" ]] ; then
        apt-get install -y cmake ninja-build
    fi

    # Android NDK
    dpkg_architecture="$(dpkg --print-architecture)"
    if [[ "$SKIP_ANDROID" != "1" ]] && [[ "$dpkg_architecture" == amd64 ]] ; then
        eval "$(cat /etc/os-release)"
        case "$VERSION_CODENAME" in
            bookworm|jammy)
                : # Not available
                ;;
            noble)
                apt-get install -y google-android-ndk-r26c-installer
                ;;
            *)
                echo "Unable to fetch Android NDK for unknown Linux distribution: $VERSION_CODENAME" >&2
                exit 1
        esac
    else
        echo "Skipping Android NDK installation on $dpkg_architecture" >&2
    fi
elif command -v dnf >/dev/null 2>&1 ; then # rhel-ubi9
    dnf update -y

    # Build dependencies
    dnf install -y sqlite-devel ncurses-devel

    # Debug symbols
    dnf debuginfo-install -y glibc
elif command -v yum >/dev/null 2>&1 ; then # amazonlinux2
    yum update -y

    # Build dependencies
    yum install -y sqlite-devel ncurses-devel

    # Debug symbols
    yum install -y yum-utils
    debuginfo-install -y glibc
fi
