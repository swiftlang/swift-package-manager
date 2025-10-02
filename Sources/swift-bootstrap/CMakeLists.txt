# This source file is part of the Swift open source project
#
# Copyright (c) 2022 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_executable(swift-bootstrap
    main.swift)
target_link_libraries(swift-bootstrap PRIVATE
  ArgumentParser
  Basics
  Build
  PackageGraph
  PackageLoading
  PackageModel
  SwiftDriver
  TSCBasic
  TSCUtility
  XCBuildSupport
  SwiftBuildSupport)
