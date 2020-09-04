# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(Workspace
  Destination.swift
  Diagnostics.swift
  Export.swift
  InitPackage.swift
  misc.swift
  ResolverPrecomputationProvider.swift
  ToolsVersionWriter.swift
  UserToolchain.swift
  Workspace.swift
  WorkspaceState.swift)
target_link_libraries(Workspace PUBLIC
  TSCBasic
  TSCUtility
  Build
  PackageGraph
  PackageModel
  SourceControl
  Xcodeproj)
# NOTE(compnerd) workaround for CMake not setting up include flags yet
set_target_properties(Workspace PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

if(USE_CMAKE_INSTALL)
install(TARGETS Workspace
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)
endif()
