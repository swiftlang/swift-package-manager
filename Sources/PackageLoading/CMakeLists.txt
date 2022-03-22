# This source file is part of the Swift open source project
#
# Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(PackageLoading
  ContextModel.swift
  Diagnostics.swift
  IdentityResolver.swift
  ManifestLoader.swift
  ManifestLoader+Validation.swift
  ModuleMapGenerator.swift
  PackageBuilder.swift
  ManifestJSONParser.swift
  PkgConfig.swift
  Target+PkgConfig.swift
  TargetSourcesBuilder.swift
  ToolsVersionParser.swift)
target_link_libraries(PackageLoading PUBLIC
  TSCBasic
  Basics
  PackageModel
  SourceControl
  TSCUtility)
target_link_libraries(PackageLoading PUBLIC
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)
# NOTE(compnerd) workaround for CMake not setting up include flags yet
set_target_properties(PackageLoading PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

if(USE_CMAKE_INSTALL)
install(TARGETS PackageLoading
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)
endif()
set_property(GLOBAL APPEND PROPERTY SwiftPM_EXPORTS PackageLoading)
