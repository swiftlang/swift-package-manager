# This source file is part of the Swift open source project
#
# Copyright (c) 2020-2021 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(PackageCollectionsModel STATIC
  PackageCollectionModel.swift
  PackageCollectionModel+v1.swift)
target_link_libraries(PackageCollectionsModel PUBLIC
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)

set_target_properties(PackageCollectionsModel PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

set_property(GLOBAL APPEND PROPERTY SwiftPM_EXPORTS PackageCollectionsModel)
