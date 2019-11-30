# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(Commands
  APIDigester.swift
  Completions+bash.swift
  Completions+zsh.swift
  Describe.swift
  Error.swift
  GenerateLinuxMain.swift
  MultiRootSupport.swift
  Options.swift
  show-dependencies.swift
  SwiftBuildTool.swift
  SwiftPackageTool.swift
  SwiftRunTool.swift
  SwiftTestTool.swift
  SwiftTool.swift
  WatchmanHelper.swift)
target_link_libraries(Commands PUBLIC
  TSCBasic
  Build
  PackageGraph
  SourceControl
  TSCUtility
  Xcodeproj
  Workspace)
# NOTE(compnerd) workaround for CMake not setting up include flags yet
set_target_properties(Commands PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

install(TARGETS Commands
  ARCHIVE DESTINATION lib/swift$<$<NOT:$<BOOL:${BUILD_SHARED_LIBS}>>:_static>/$<LOWER_CASE:${CMAKE_SYSTEM_NAME}> COMPONENT libs
  LIBRARY DESTINATION lib/swift$<$<NOT:$<BOOL:${BUILD_SHARED_LIBS}>>:_static>/$<LOWER_CASE:${CMAKE_SYSTEM_NAME}> COMPONENT libs
  RUNTIME DESTINATION bin COMPONENT libs)
install(FILES
  $<TARGET_PROPERTY:Commands,Swift_MODULE_DIRECTORY>/Commands.swiftdoc
  $<TARGET_PROPERTY:Commands,Swift_MODULE_DIRECTORY>/Commands.swiftmodule
  DESTINATION lib/swift/pm COMPONENT libs)
