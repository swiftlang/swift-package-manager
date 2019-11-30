# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(PackageModel
  BuildSettings.swift
  Manifest.swift
  Package.swift
  PackageModel+Codable.swift
  Platform.swift
  Product.swift
  ResolvedModels.swift
  Resource.swift
  Sources.swift
  Target.swift
  ToolsVersion.swift)
target_link_libraries(PackageModel PUBLIC
  TSCBasic
  TSCUtility)
# NOTE(compnerd) workaround for CMake not setting up include flags yet
set_target_properties(PackageModel PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

install(TARGETS PackageModel
  ARCHIVE DESTINATION lib/swift$<$<NOT:$<BOOL:${BUILD_SHARED_LIBS}>>:_static>/$<LOWER_CASE:${CMAKE_SYSTEM_NAME}> COMPONENT libs
  LIBRARY DESTINATION lib/swift$<$<NOT:$<BOOL:${BUILD_SHARED_LIBS}>>:_static>/$<LOWER_CASE:${CMAKE_SYSTEM_NAME}> COMPONENT libs
  RUNTIME DESTINATION bin COMPONENT libs)
install(FILES
  $<TARGET_PROPERTY:PackageModel,Swift_MODULE_DIRECTORY>/PackageModel.swiftdoc
  $<TARGET_PROPERTY:PackageModel,Swift_MODULE_DIRECTORY>/PackageModel.swiftmodule
  DESTINATION lib/swift/pm COMPONENT libs)
