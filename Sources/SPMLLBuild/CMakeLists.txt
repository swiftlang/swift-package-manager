# This source file is part of the Swift open source project
#
# Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(SPMLLBuild STATIC
  llbuild.swift)
# NOTE(compnerd) workaround for CMake not setting up include flags yet
set_target_properties(SPMLLBuild PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(SPMLLBuild PUBLIC
  Basics
  TSCBasic
  TSCUtility
  llbuildSwift)
