# This source file is part of the Swift open source project
#
# Copyright (c) 2023 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(PackageManifest
  Serialization/ManifestEncoding.swift
  Model/DeploymentTarget.swift
  Model/Platform.swift
  Model/Package.swift
  Model/Dependency.swift
  Model/Module.swift
  DSL/DeploymentTargetDSL.swift
  DSL/DependencyyDSL.swift
  DSL/ModuleDSL.swift
  DSL/PackageDSL.swift)

target_compile_options(PackageManifest PUBLIC
  $<$<COMPILE_LANGUAGE:Swift>:-package-description-version$<SEMICOLON>999.0>
  $<$<COMPILE_LANGUAGE:Swift>:-DSERIALIZATION>)

if(CMAKE_HOST_SYSTEM_NAME STREQUAL Darwin)
  target_link_options(PackageManifest PRIVATE
    "SHELL:-Xlinker -install_name -Xlinker @rpath/libPackageManifest.dylib")
endif()

set_target_properties(PackageManifest PROPERTIES
    Swift_MODULE_NAME PackageManifest
    Swift_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/pm/ManifestAPI
    INSTALL_NAME_DIR \\@rpath
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/ManifestAPI
    OUTPUT_NAME PackageManifest
    ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/ManifestAPI
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/ManifestAPI
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/ManifestAPI
)

if(NOT CMAKE_SYSTEM_NAME STREQUAL Darwin)
  target_link_libraries(PackageManifest PRIVATE
    Foundation)
  target_link_options(PackageManifest PRIVATE
    "SHELL:-no-toolchain-stdlib-rpath")
  set_target_properties(PackageManifest PROPERTIES
    BUILD_WITH_INSTALL_RPATH TRUE
    INSTALL_RPATH "$ORIGIN/../../$<LOWER_CASE:${CMAKE_SYSTEM_NAME}>")
endif()

install(FILES
  ${CMAKE_BINARY_DIR}/pm/ManifestAPI/PackageManifest.swiftmodule
  ${CMAKE_BINARY_DIR}/pm/ManifestAPI/PackageManifest.swiftdoc
  DESTINATION lib/swift/pm/ManifestAPI
)

install(TARGETS PackageManifest
  DESTINATION lib/swift/pm/ManifestAPI)
