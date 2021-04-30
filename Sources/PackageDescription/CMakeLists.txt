# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(PackageDescription
  BuildSettings.swift
  LanguageStandardSettings.swift
  PackageDescription.swift
  PackageDependency.swift
  PackageRequirement.swift
  Product.swift
  Resource.swift
  SupportedPlatforms.swift
  Target.swift
  Version.swift
  Version+StringLiteralConvertible.swift)

target_compile_options(PackageDescription PUBLIC
  $<$<COMPILE_LANGUAGE:Swift>:-package-description-version$<SEMICOLON>999.0>)
target_compile_options(PackageDescription PUBLIC
  $<$<COMPILE_LANGUAGE:Swift>:-enable-library-evolution>)

if(CMAKE_HOST_SYSTEM_NAME STREQUAL Darwin)
  set(SWIFT_INTERFACE_PATH ${CMAKE_BINARY_DIR}/pm/ManifestAPI/PackageDescription.swiftinterface)
  target_compile_options(PackageDescription PUBLIC
    $<$<COMPILE_LANGUAGE:Swift>:-emit-module-interface-path$<SEMICOLON>${SWIFT_INTERFACE_PATH}>)
  target_link_options(PackageDescription PRIVATE
    "SHELL:-Xlinker -install_name -Xlinker @rpath/libPackageDescription.dylib")
endif()

set_target_properties(PackageDescription PROPERTIES
    Swift_MODULE_NAME PackageDescription
    Swift_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/pm/ManifestAPI
    INSTALL_NAME_DIR \\@rpath
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/ManifestAPI
    OUTPUT_NAME PackageDescription
    ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/ManifestAPI
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/ManifestAPI
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/ManifestAPI
)

if(NOT CMAKE_SYSTEM_NAME STREQUAL Darwin)
  if(Foundation_FOUND)
    target_link_libraries(PackageDescription PRIVATE
      Foundation)
  endif()
  target_link_options(PackageDescription PRIVATE
    "SHELL:-no-toolchain-stdlib-rpath")
  set_target_properties(PackageDescription PROPERTIES
    BUILD_WITH_INSTALL_RPATH TRUE
    INSTALL_RPATH "$ORIGIN/../../$<LOWER_CASE:${CMAKE_SYSTEM_NAME}>")
endif()

if(CMAKE_HOST_SYSTEM_NAME STREQUAL Darwin)
  install(FILES
    ${CMAKE_BINARY_DIR}/pm/ManifestAPI/PackageDescription.swiftinterface
    ${CMAKE_BINARY_DIR}/pm/ManifestAPI/PackageDescription.swiftdoc
    DESTINATION lib/swift/pm/ManifestAPI
  )
else()
  install(FILES
    ${CMAKE_BINARY_DIR}/pm/ManifestAPI/PackageDescription.swiftmodule
    ${CMAKE_BINARY_DIR}/pm/ManifestAPI/PackageDescription.swiftdoc
    DESTINATION lib/swift/pm/ManifestAPI
  )
endif()

install(TARGETS PackageDescription
  DESTINATION lib/swift/pm/ManifestAPI)
