# This source file is part of the Swift open source project
#
# Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_compile_definitions(USE_IMPL_ONLY_IMPORTS)

add_subdirectory(_AsyncFileSystem)
add_subdirectory(Basics)
add_subdirectory(BinarySymbols)
add_subdirectory(Build)
add_subdirectory(Commands)
add_subdirectory(CoreCommands)
add_subdirectory(DriverSupport)
add_subdirectory(LLBuildManifest)
add_subdirectory(PackageCollections)
add_subdirectory(PackageCollectionsModel)
add_subdirectory(PackageCollectionsSigning)
add_subdirectory(PackageFingerprint)
add_subdirectory(PackageGraph)
add_subdirectory(PackageLoading)
add_subdirectory(PackageModel)
add_subdirectory(PackageRegistry)
add_subdirectory(PackageRegistryCommand)
add_subdirectory(PackageSigning)
add_subdirectory(QueryEngine)
add_subdirectory(SBOMModel)
add_subdirectory(SourceControl)
add_subdirectory(SourceKitLSPAPI)
add_subdirectory(SPMBuildCore)
add_subdirectory(SPMLLBuild)
add_subdirectory(SPMSQLite3)
add_subdirectory(SwiftFixIt)
add_subdirectory(swift-bootstrap)
add_subdirectory(swift-build)
add_subdirectory(swift-experimental-sdk)
add_subdirectory(swift-sdk)
add_subdirectory(swift-package)
add_subdirectory(swift-run)
add_subdirectory(swift-test)
add_subdirectory(SwiftPMBuildServer)
add_subdirectory(SwiftSDKCommand)
add_subdirectory(Workspace)
add_subdirectory(XCBuildSupport)
add_subdirectory(SwiftBuildSupport)
add_subdirectory(tsan_utils)

if(SwiftPM_ENABLE_RUNTIME)
  add_subdirectory(Runtimes)
  # NOTE: maintain the custom output directory for the ManifestAPI modules to
  # allow the boostrap scripts to continue functioning as they have historically.
  # This is unnecessary with the split runtime build, but is left here to
  # minimize disruption.
  set_target_properties(CompilerPluginSupport PROPERTIES
    Swift_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/pm/ManifestAPI
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/ManifestAPI
    ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/ManifestAPI
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/ManifestAPI
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/ManifestAPI)
  set_target_properties(PackageDescription PROPERTIES
    Swift_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/pm/ManifestAPI
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/ManifestAPI
    ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/ManifestAPI
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/ManifestAPI
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/ManifestAPI)
  set_target_properties(PackagePlugin PROPERTIES
    Swift_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/pm/PluginAPI
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/PluginAPI
    ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/PluginAPI
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/PluginAPI
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/PluginAPI)
endif()
