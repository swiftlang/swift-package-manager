# This source file is part of the Swift open source project
#
# Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(PackageLoading
  ContextModel.swift
  Diagnostics.swift
  ManifestJSONParser.swift
  ManifestLoader.swift
  ManifestLoader+Validation.swift
  ManifestSignatureParser.swift
  ModuleMapGenerator.swift
  PackageBuilder.swift
  PackageDescriptionSerialization.swift
  Platform.swift
  PkgConfig.swift
  RegistryReleaseMetadataSerialization.swift
  Target+PkgConfig.swift
  TargetSourcesBuilder.swift
  ToolsVersionParser.swift)
target_link_libraries(PackageLoading PUBLIC
  TSCBasic
  Basics
  PackageModel
  TSCUtility)
target_link_libraries(PackageLoading PUBLIC
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)
target_link_libraries(PackageLoading PRIVATE
  SourceControl)
# NOTE(compnerd) workaround for CMake not setting up include flags yet
set_target_properties(PackageLoading PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

install(TARGETS PackageLoading
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)
set_property(GLOBAL APPEND PROPERTY SwiftPM_EXPORTS PackageLoading)
