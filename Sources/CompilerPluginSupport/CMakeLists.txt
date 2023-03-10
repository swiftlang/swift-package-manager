# This source file is part of the Swift open source project
#
# Copyright (c) 2023 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(CompilerPluginSupport
  TargetExtensions.swift)
target_link_libraries(CompilerPluginSupport PRIVATE
  PackageDescription)

target_compile_options(CompilerPluginSupport PUBLIC
  $<$<COMPILE_LANGUAGE:Swift>:-package-description-version$<SEMICOLON>999.0>)

if(CMAKE_HOST_SYSTEM_NAME STREQUAL Darwin)
  target_link_options(CompilerPluginSupport PRIVATE
    "SHELL:-Xlinker -install_name -Xlinker @rpath/CompilerPluginSupport.dylib")
endif()

set_target_properties(CompilerPluginSupport PROPERTIES
    Swift_MODULE_NAME CompilerPluginSupport
    Swift_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/pm/ManifestAPI
    INSTALL_NAME_DIR \\@rpath
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/ManifestAPI
    OUTPUT_NAME CompilerPluginSupport
    ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/ManifestAPI
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/ManifestAPI
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/ManifestAPI
)

if(NOT CMAKE_SYSTEM_NAME STREQUAL Darwin)
  target_link_libraries(CompilerPluginSupport PRIVATE
    Foundation)
  target_link_options(CompilerPluginSupport PRIVATE
    "SHELL:-no-toolchain-stdlib-rpath")
  set_target_properties(CompilerPluginSupport PROPERTIES
    BUILD_WITH_INSTALL_RPATH TRUE
    INSTALL_RPATH "$ORIGIN/../../$<LOWER_CASE:${CMAKE_SYSTEM_NAME}>")
endif()

install(FILES
  ${CMAKE_BINARY_DIR}/pm/ManifestAPI/CompilerPluginSupport.swiftmodule
  ${CMAKE_BINARY_DIR}/pm/ManifestAPI/CompilerPluginSupport.swiftdoc
  DESTINATION lib/swift/pm/ManifestAPI
)

install(TARGETS CompilerPluginSupport
  DESTINATION lib/swift/pm/ManifestAPI)
