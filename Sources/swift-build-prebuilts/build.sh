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
swift run swift-build-prebuilts --stage-dir ~/swift/stage --build --test-signing \
    --version 600.0.1 \
    --version 601.0.1 \
    --version $(git ls-remote --tags https://github.com/swiftlang/swift-syntax '*.*.*' | cut -d '/' -f 3 | grep ^602 | tail -1)
