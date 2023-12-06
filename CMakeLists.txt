# This source file is part of the Swift open source project
#
# Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

cmake_minimum_required(VERSION 3.19)

list(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/cmake/modules)

project(SwiftPM LANGUAGES C Swift)

set(CMAKE_Swift_LANGUAGE_VERSION 5)
set(CMAKE_Swift_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/swift)

set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

option(BUILD_SHARED_LIBS "Build shared libraries by default" YES)
option(FIND_PM_DEPS "Search for all external Package Manager dependencies" YES)

string(COMPARE EQUAL ${CMAKE_SYSTEM_NAME} Windows CMAKE_INSTALL_DEFAULT)
option(USE_CMAKE_INSTALL
  "Install build products using cmake's install() instead of the bootstrap script's install()"
  ${CMAKE_INSTALL_DEFAULT})

if(BUILD_SHARED_LIBS)
  set(CMAKE_POSITION_INDEPENDENT_CODE YES)
endif()

add_compile_options(-DUSE_IMPL_ONLY_IMPORTS)

if(FIND_PM_DEPS)
  find_package(SwiftSystem CONFIG REQUIRED)
  find_package(TSC CONFIG REQUIRED)

  find_package(LLBuild CONFIG)
  if(NOT LLBuild_FOUND)
    find_package(LLBuild REQUIRED)
  endif()

  find_package(ArgumentParser CONFIG REQUIRED)
  find_package(SwiftDriver CONFIG REQUIRED)
  find_package(SwiftCollections CONFIG REQUIRED)
  find_package(SwiftASN1 CONFIG REQUIRED)
  find_package(SwiftCertificates CONFIG REQUIRED)
  find_package(SwiftCrypto CONFIG REQUIRED)
endif()

find_package(dispatch QUIET)
find_package(Foundation QUIET)
find_package(SQLite3 REQUIRED)

add_subdirectory(Sources)
add_subdirectory(cmake/modules)
