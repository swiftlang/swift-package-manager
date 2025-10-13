# This source file is part of the Swift open source project
#
# Copyright (c) 2025 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

cmake_minimum_required(VERSION 3.29)

if(POLICY CMP0157 AND CMAKE_Swift_COMPILER_USE_OLD_DRIVER)
  cmake_policy(SET CMP0157 OLD)
endif()

project(SwiftPMRuntime
  LANGUAGES Swift)

# TODO(compnerd) C is being enabled as a workaround for `GNUInstallDirs` not
# being aware of Swift-only projects. Remove this once that is updated and we
# have updated to a newer CMake minimum version.
enable_language(C)
include(GNUInstallDirs)

set(CMAKE_INSTALL_NAME_DIR "@rpath")
set(CMAKE_INSTALL_RPATH "$ORIGIN/../../$<LOWER_CASE:${CMAKE_SYSTEM_NAME}>")
set(CMAKE_MSVC_RUNTIME_LIBRARY MultiThreadedDLL)
set(CMAKE_POSITION_INDEPENDENT_CODE ${BUILD_SHARED_LIBS})
set(CMAKE_Swift_LANGUAGE_VERSION 5)
set(CMAKE_Swift_COMPILE_OPTIONS_MSVC_RUNTIME_LIBRARY MultiThreadedDLL)

set(SwiftPMRuntime_ENABLE_LIBRARY_EVOLUTION YES)
add_compile_options(-enable-library-evolution)

add_compile_options(-package-description-version 999.0)

list(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/cmake/modules)
include(PlatformInfo)
include(EmitSwiftInterface)
include(InstallSwiftInterface)

add_subdirectory(PackageDescription)
add_subdirectory(CompilerPluginSupport)
add_subdirectory(PackagePlugin)
