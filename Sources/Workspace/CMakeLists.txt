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
  ManagedDependency.swift
  ToolsVersionWriter.swift
  UserToolchain.swift
  Workspace.swift
  misc.swift)
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

install(TARGETS Workspace
  ARCHIVE DESTINATION lib/swift$<$<NOT:$<BOOL:${BUILD_SHARED_LIBS}>>:_static>/$<LOWER_CASE:${CMAKE_SYSTEM_NAME}> COMPONENT libs
  LIBRARY DESTINATION lib/swift$<$<NOT:$<BOOL:${BUILD_SHARED_LIBS}>>:_static>/$<LOWER_CASE:${CMAKE_SYSTEM_NAME}> COMPONENT libs
  RUNTIME DESTINATION bin COMPONENT libs)
install(FILES
  $<TARGET_PROPERTY:Workspace,Swift_MODULE_DIRECTORY>/Workspace.swiftdoc
  $<TARGET_PROPERTY:Workspace,Swift_MODULE_DIRECTORY>/Workspace.swiftmodule
  DESTINATION lib/swift/pm COMPONENT libs)
