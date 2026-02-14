#!/bin/bash
##===----------------------------------------------------------------------===##
##
## This source file is part of the Swift open source project
##
## Copyright (c) 2014-2022 Apple Inc. and the Swift project authors
## Licensed under Apache License v2.0 with Runtime Library Exception
##
## See http://swift.org/LICENSE.txt for license information
## See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
##
##===----------------------------------------------------------------------===##

## run from the package root for swiftpm
set -ex

build-dep() {
    dep=$1; shift
    name=$1; shift
    cmake -G Ninja -B .build/cmake/$dep -S .build/checkouts/$dep $DEPS -DBUILD_TESTING=NO $*
    cmake --build .build/cmake/$dep
    DEPS="$DEPS -D${name}_DIR=$(pwd)/.build/cmake/${dep}/cmake/modules"
}

[ -d .build ] || swift package resolve

rm -fr .build/cmake

build-dep swift-system SwiftSystem
build-dep swift-tools-support-core TSC
build-dep swift-llbuild LLBuild -DLLBUILD_SUPPORT_BINDINGS=Swift
build-dep swift-argument-parser ArgumentParser
build-dep swift-driver SwiftDriver
build-dep swift-collections SwiftCollections
build-dep swift-asn1 SwiftASN1
build-dep swift-certificates SwiftCertificates
build-dep swift-crypto SwiftCrypto
build-dep swift-tools-protocols SwiftToolsProtocols
build-dep swift-build SwiftBuild
build-dep swift-syntax SwiftSyntax

cmake -G Ninja -B .build/cmake/swiftpm -S . $DEPS
cmake --build .build/cmake/swiftpm

cp -R .build/cmake/swiftpm/Sources/Runtimes/PackageDescription/PackageDescription.swiftmodule .build/cmake/swiftpm/bin
cp .build/cmake/swiftpm/pm/ManifestAPI/libPackageDescription.dylib .build/cmake/swiftpm/bin

if [ "$(uname -s)" == "Darwin" ]; then
    .build/cmake/swiftpm/bin/swift-build --product swiftpm-testing-helper
    cp .build/debug/swiftpm-testing-helper .build/cmake/swiftpm/bin
fi

mkdir -p .build/cmake/test
cd .build/cmake/test
../swiftpm/bin/swift-package init
../swiftpm/bin/swift-test
