#!/bin/bash
##===----------------------------------------------------------------------===##
##
## This source file is part of the Swift open source project
##
## Copyright (c) 2024 Apple Inc. and the Swift project authors
## Licensed under Apache License v2.0 with Runtime Library Exception
##
## See http://swift.org/LICENSE.txt for license information
## See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
##
##===----------------------------------------------------------------------===##

# A `realpath` alternative using the default C implementation.
filepath() {
  [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

ROOT="$(dirname $(dirname $(filepath $0)))"

cd $ROOT

rm -rf archives

xcodebuild archive \
-project FooKit.xcodeproj \
-scheme FooKit \
-configuration Release \
-destination "generic/platform=macOS" \
-archivePath "archives/macOS" \
SKIP_INSTALL=NO \
BUILD_LIBRARY_FOR_DISTRIBUTION=YES

xcodebuild \
-create-xcframework \
-archive archives/macOS.xcarchive -framework FooKit.framework \
-output ../FooKit.xcframework
