# This source file is part of the Swift open source project
#
# Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(PackageRegistryCommand
  PackageRegistryCommand+Auth.swift
  PackageRegistryCommand+Publish.swift
  PackageRegistryCommand.swift)
# NOTE(compnerd) workaround for CMake not setting up include flags yet
set_target_properties(PackageRegistryCommand PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(PackageRegistryCommand PUBLIC
  Basics
  Commands
  CoreCommands
  PackageFingerprint
  PackageModel
  PackageRegistry
  PackageSigning
  Workspace
  ArgumentParser
  TSCBasic
  TSCUtility
  X509)
if(NOT APPLE)
  if(Foundation_FOUND)
    target_link_directories(PackageRegistryCommand PRIVATE
      $<TARGET_LINKER_FILE_DIR:Fooundation>)
  endif()
endif()

install(TARGETS PackageRegistryCommand
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)
