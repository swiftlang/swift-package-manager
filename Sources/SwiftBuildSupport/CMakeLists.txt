# This source file is part of the Swift open source project
#
# Copyright (c) 2025 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(SwiftBuildSupport STATIC
  PIF.swift
  PIFBuilder.swift
  BuildSystem.swift
  SwiftBuildSystem.swift)
target_link_libraries(SwiftBuildSupport PUBLIC
  Build
  DriverSupport
  TSCBasic
  TSCUtility
  PackageGraph
)

set_target_properties(SwiftBuildSupport PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
