# This source file is part of the Swift open source project
#
# Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(PackageCollectionsModel
  PackageCollectionModel+v1.swift
  PackageCollectionModel.swift)
# NOTE(compnerd) workaround for CMake not setting up include flags yet
set_target_properties(PackageCollectionsModel PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
if(NOT APPLE)
  if(Foundation_FOUND)
    target_link_directories(PackageCollectionsModel PRIVATE
      $<TARGET_LINKER_FILE_DIR:Fooundation>)
  endif()
endif()

install(TARGETS PackageCollectionsModel
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)
