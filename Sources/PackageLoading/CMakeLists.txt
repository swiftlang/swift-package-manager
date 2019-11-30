# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(PackageLoading
  Diagnostics.swift
  ManifestBuilder.swift
  ManifestLoader.swift
  ModuleMapGenerator.swift
  PackageBuilder.swift
  PackageDescription4Loader.swift
  Target+PkgConfig.swift
  TargetSourcesBuilder.swift
  ToolsVersionLoader.swift
  UserManifestResources.swift)
target_link_libraries(PackageLoading PUBLIC
  TSCBasic
  PackageModel
  TSCUtility
  SPMLLBuild)
# NOTE(compnerd) workaround for CMake not setting up include flags yet
set_target_properties(PackageLoading PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})


install(TARGETS PackageLoading
  ARCHIVE DESTINATION lib/swift$<$<NOT:$<BOOL:${BUILD_SHARED_LIBS}>>:_static>/$<LOWER_CASE:${CMAKE_SYSTEM_NAME}> COMPONENT libs
  LIBRARY DESTINATION lib/swift$<$<NOT:$<BOOL:${BUILD_SHARED_LIBS}>>:_static>/$<LOWER_CASE:${CMAKE_SYSTEM_NAME}> COMPONENT libs
  RUNTIME DESTINATION bin COMPONENT libs)
install(FILES
  $<TARGET_PROPERTY:PackageLoading,Swift_MODULE_DIRECTORY>/PackageLoading.swiftdoc
  $<TARGET_PROPERTY:PackageLoading,Swift_MODULE_DIRECTORY>/PackageLoading.swiftmodule
  DESTINATION lib/swift/pm COMPONENT libs)
