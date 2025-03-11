# This source file is part of the Swift open source project
#
# Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

if(POLICY CMP0091)
  cmake_policy(SET CMP0091 NEW)
endif()

cmake_minimum_required(VERSION 3.24)

list(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/cmake/modules)

project(SwiftPM LANGUAGES C Swift)

option(BUILD_SHARED_LIBS "Build shared libraries by default" YES)
option(FIND_PM_DEPS "Search for all external Package Manager dependencies" YES)

set(CMAKE_Swift_LANGUAGE_VERSION 5)
set(CMAKE_Swift_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/swift)
set(CMAKE_Swift_COMPILE_OPTIONS_MSVC_RUNTIME_LIBRARY MultiThreadedDLL)

set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

set(CMAKE_MSVC_RUNTIME_LIBRARY MultiThreadedDLL)
set(CMAKE_POSITION_INDEPENDENT_CODE ${BUILD_SHARED_LIBS})

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

# Enable `package` modifier for the whole package.
if(CMAKE_SYSTEM_NAME STREQUAL FreeBSD)
  add_compile_options("$<$<COMPILE_LANGUAGE:Swift>:-package-name;SwiftPM>" -L/usr/local/lib)
else()
  add_compile_options("$<$<COMPILE_LANGUAGE:Swift>:-package-name;SwiftPM>")
endif()

add_subdirectory(BuildSupport/SwiftSyntax)
add_subdirectory(Sources)
add_subdirectory(cmake/modules)
