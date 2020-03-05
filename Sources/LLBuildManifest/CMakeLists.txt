# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(LLBuildManifest
  BuildManifest.swift
  Command.swift
  ManifestWriter.swift
  Node.swift
  Target.swift
  Tools.swift)
target_link_libraries(LLBuildManifest PUBLIC
  TSCBasic)

# NOTE(compnerd) workaround for CMake not setting up include flags yet
set_target_properties(LLBuildManifest PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

if(CMAKE_SYSTEM_NAME STREQUAL Windows)
    install(TARGETS LLBuildManifest
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)
endif()
