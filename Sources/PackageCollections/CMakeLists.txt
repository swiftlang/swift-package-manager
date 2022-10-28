# This source file is part of the Swift open source project
#
# Copyright (c) 2020-2022 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(PackageCollections STATIC
  Model/Collection.swift
  Model/CVE.swift
  Model/License.swift
  Model/PackageTypes.swift
  Model/PackageList.swift
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
  PackageCollections+CertificatePolicy.swift
  PackageCollections+Configuration.swift
  PackageCollections+Storage.swift
  PackageCollections+Validation.swift
  PackageIndex.swift
  PackageIndex+Configuration.swift
  PackageIndexAndCollections.swift
  Utility.swift)
target_link_libraries(PackageCollections PUBLIC
  TSCBasic
  TSCUtility
  Basics
  Crypto
  PackageCollectionsModel
  PackageCollectionsSigning
  PackageModel
  SourceControl)
# NOTE(compnerd) workaround for CMake not setting up include flags yet
set_target_properties(PackageCollections PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

set_property(GLOBAL APPEND PROPERTY SwiftPM_EXPORTS PackageCollections)
