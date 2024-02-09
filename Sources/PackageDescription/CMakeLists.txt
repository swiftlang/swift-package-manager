# This source file is part of the Swift open source project
#
# Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(PackageDescription STATIC
  BuildSettings.swift
  Context.swift
  ContextModel.swift
  LanguageStandardSettings.swift
  PackageDescription.swift
  PackageDescriptionSerialization.swift
  PackageDescriptionSerializationConversion.swift
  PackageDependency.swift
  PackageRequirement.swift
  Product.swift
  Resource.swift
  SupportedPlatforms.swift
  Target.swift
  Version.swift
  Version+StringLiteralConvertible.swift)
target_compile_options(PackageDescription PRIVATE
  $<$<COMPILE_LANGUAGE:Swift>:-package-description-version$<SEMICOLON>999.0>)
set_target_properties(PackageDescription PROPERTIES
    Swift_MODULE_NAME PackageDescription
    Swift_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/pm/ManifestAPI
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/ManifestAPI
    ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/ManifestAPI
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/ManifestAPI
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/ManifestAPI)

install(FILES
  ${CMAKE_BINARY_DIR}/pm/ManifestAPI/PackageDescription.swiftmodule
  ${CMAKE_BINARY_DIR}/pm/ManifestAPI/PackageDescription.swiftdoc
  DESTINATION lib/swift/pm/ManifestAPI)
install(TARGETS PackageDescription
  DESTINATION lib/swift/pm/ManifestAPI)
