# This source file is part of the Swift open source project
#
# Copyright (c) 2023 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(CompilerPluginSupport STATIC
  TargetExtensions.swift)
target_compile_options(CompilerPluginSupport PRIVATE
  $<$<COMPILE_LANGUAGE:Swift>:-package-description-version$<SEMICOLON>999.0>)
target_link_libraries(CompilerPluginSupport PRIVATE
  PackageDescription)
set_target_properties(CompilerPluginSupport PROPERTIES
    Swift_MODULE_NAME CompilerPluginSupport
    Swift_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/pm/ManifestAPI
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/ManifestAPI
    ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/ManifestAPI
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/ManifestAPI
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/ManifestAPI)

install(FILES
  ${CMAKE_BINARY_DIR}/pm/ManifestAPI/CompilerPluginSupport.swiftmodule
  ${CMAKE_BINARY_DIR}/pm/ManifestAPI/CompilerPluginSupport.swiftdoc
  DESTINATION lib/swift/pm/ManifestAPI)
install(TARGETS CompilerPluginSupport
  DESTINATION lib/swift/pm/ManifestAPI)
