# This source file is part of the Swift open source project
#
# Copyright (c) 2025 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(SwiftPMBuildServer STATIC
  DisableSigpipe.swift
  SwiftPMBuildServer.swift)
target_link_libraries(SwiftPMBuildServer PUBLIC
  Basics
  Build
  PackageGraph
  PackageLoading
  PackageModel
  SPMBuildCore
  SourceControl
  SourceKitLSPAPI
  SwiftBuildSupport
  Workspace

  SwiftBuild::SwiftBuild

  SwiftToolsProtocols::ToolsProtocolsSwiftExtensions
  SwiftToolsProtocols::BuildServerProtocol
  SwiftToolsProtocols::LanguageServerProtocol
  SwiftToolsProtocols::LanguageServerProtocolTransport

  TSCBasic)

# NOTE(compnerd) workaround for CMake not setting up include flags yet
set_target_properties(SwiftPMBuildServer PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
