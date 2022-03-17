# This source file is part of the Swift open source project
#
# Copyright (c) 2021 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(PackageRegistry STATIC
  Registry.swift
  RegistryConfiguration.swift
  RegistryClient.swift
  RegistryDownloadsManager.swift)
target_link_libraries(PackageRegistry PUBLIC
  Basics
  PackageFingerprint
  PackageLoading
  PackageModel
  TSCBasic
  TSCUtility)
# NOTE(compnerd) workaround for CMake not setting up include flags yet
set_target_properties(PackageRegistry PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

set_property(GLOBAL APPEND PROPERTY SwiftPM_EXPORTS PackageRegistry)
