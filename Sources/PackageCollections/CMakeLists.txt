# This source file is part of the Swift.org open source project
#
# Copyright (c) 2020 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(PackageCollections
  JSONModel/JSONCollection.swift
  JSONModel/JSONCollection+v1.swift
  Model/Collection.swift
  Model/CVE.swift
  Model/License.swift
  Model/Package.swift
  Model/Search.swift
  Model/TargetListResult.swift
  Providers/GitHubPackageMetadataProvider.swift
  Providers/JSONPackageCollectionProvider.swift
  Providers/PackageCollectionProvider.swift
  Providers/PackageMetadataProvider.swift
  Storage/FilePackageCollectionsSourcesStorage.swift
  Storage/PackageCollectionsSourcesStorage.swift
  Storage/PackageCollectionsStorage.swift
  Storage/SQLitePackageCollectionsStorage.swift
  Storage/Trie.swift
  API.swift
  PackageCollections.swift
  PackageCollections+Configuration.swift
  PackageCollections+Storage.swift
  PackageCollections+Validation.swift
  Utility.swift)
target_link_libraries(PackageCollections PUBLIC
  TSCBasic
  TSCUtility
  Basics
  PackageModel
  SourceControl)
# NOTE(compnerd) workaround for CMake not setting up include flags yet
set_target_properties(PackageCollections PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

if(USE_CMAKE_INSTALL)
install(TARGETS PackageCollections
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)
endif()
set_property(GLOBAL APPEND PROPERTY SwiftPM_EXPORTS PackageCollections)
