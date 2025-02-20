# This source file is part of the Swift open source project
#
# Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(SourceKitLSPAPI STATIC
  BuildDescription.swift
  PluginTargetBuildDescription.swift)
target_link_libraries(SourceKitLSPAPI PUBLIC
  Basics
  Build
  PackageGraph
  SPMBuildCore)
target_link_libraries(SourceKitLSPAPI PRIVATE
  PackageLoading
  PackageModel)

# NOTE(compnerd) workaround for CMake not setting up include flags yet
set_target_properties(SourceKitLSPAPI PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

set_property(GLOBAL APPEND PROPERTY SwiftPM_EXPORTS SourceKitLSPAPI)
