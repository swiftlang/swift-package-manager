# This source file is part of the Swift open source project
#
# Copyright (c) 2021 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(PackageFingerprint STATIC
  FilePackageFingerprintStorage.swift
  Model.swift
  PackageFingerprintStorage.swift)
target_link_libraries(PackageFingerprint PUBLIC
  Basics
  PackageModel
  TSCBasic
  TSCUtility)
# NOTE(compnerd) workaround for CMake not setting up include flags yet
set_target_properties(PackageFingerprint PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
