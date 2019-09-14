# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(Build
  BuildDelegate.swift
  BuildPlan.swift
  Command.swift
  llbuild.swift
  Sanitizers.swift
  SwiftCompilerOutputParser.swift
  Toolchain.swift
  ToolProtocol.swift
  Triple.swift)
target_link_libraries(Build PUBLIC
  TSCBasic
  PackageGraph)
# NOTE(compnerd) workaround for CMake not setting up include flags yet
set_target_properties(Build PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

install(TARGETS Build
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)
