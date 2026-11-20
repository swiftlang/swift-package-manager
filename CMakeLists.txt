# This source file is part of the Swift open source project
#
# Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

cmake_minimum_required(VERSION 3.29)

list(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/cmake/modules)

project(SwiftPM LANGUAGES C Swift)

option(BUILD_SHARED_LIBS "Build shared libraries by default" YES)
option(FIND_PM_DEPS "Search for all external Package Manager dependencies" YES)
option(SwiftPM_ENABLE_RUNTIME "Build the runtime" YES)

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
  find_package(SwiftSubprocess CONFIG REQUIRED)
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
  find_package(SwiftToolsProtocols CONFIG REQUIRED)
  find_package(SwiftBuild CONFIG REQUIRED)
endif()

find_package(dispatch QUIET)
find_package(Foundation QUIET)

# Swift code imports the `SQLite3` module provided by the SDK on Darwin, and the
# `SwiftToolchainCSQLite` module from swift-toolchain-sqlite everywhere else.
set(SwiftPM_USE_VENDORED_SQLite3 NO)
if(CMAKE_SYSTEM_NAME STREQUAL Darwin)
  find_package(SQLite3 REQUIRED)
else()
  find_package(SQLite3 QUIET)
  if(SQLite3_FOUND)
    # A system SQLite3 does not come with the `SwiftToolchainCSQLite` module,
    # so only use a found SQLite3 if it is the one from swift-toolchain-sqlite.
    set(SwiftPM_SQLite3_MODULEMAP "${SQLite3_INCLUDE_DIR}/module.modulemap")
    if(NOT EXISTS "${SwiftPM_SQLite3_MODULEMAP}")
      set(SQLite3_FOUND NO)
    else()
      file(STRINGS "${SwiftPM_SQLite3_MODULEMAP}" SwiftPM_SQLite3_MODULE
        REGEX "module[ \t]+SwiftToolchainCSQLite")
      if(NOT SwiftPM_SQLite3_MODULE)
        set(SQLite3_FOUND NO)
      endif()
    endif()
  endif()
  if(NOT SQLite3_FOUND)
    include(FetchContent)

    message(STATUS "Vendoring SQLite3")
    FetchContent_Declare(SQLite
      GIT_REPOSITORY https://github.com/swiftlang/swift-toolchain-sqlite
      GIT_TAG 1.0.9)

    FetchContent_MakeAvailable(SQLite)

    if(NOT TARGET SQLite::SQLite3)
      add_library(SQLite::SQLite3 ALIAS SQLite3)
    endif()
    set(SwiftPM_USE_VENDORED_SQLite3 YES)
  endif()
endif()

# Enable `package` modifier for the whole package.
add_compile_options("$<$<COMPILE_LANGUAGE:Swift>:SHELL:-package-name swift_package_manager>")
if(CMAKE_SYSTEM_NAME STREQUAL FreeBSD)
  link_directories(/usr/local/lib)
endif()

add_subdirectory(BuildSupport/SwiftSyntax)
add_subdirectory(Sources)
add_subdirectory(cmake/modules)
