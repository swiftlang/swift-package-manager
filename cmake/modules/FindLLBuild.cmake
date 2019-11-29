# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

if(TARGET llbuildSwift)
  return()
endif()

include(CMakeFindFrameworks)
cmake_find_frameworks(llbuild)
if(llbuild_FRAMEWORKS)
  if(NOT TARGET llbuildSwift)
    add_library(llbuildSwift UNKNOWN IMPORTED)
    set_target_properties(llbuildSwift PROPERTIES
      FRAMEWORK TRUE
      INTERFACE_COMPILE_OPTIONS -F${llbuild_FRAMEWORKS}
      IMPORTED_LOCATION ${llbuild_FRAMEWORKS}/llbuild.framework/llbuild)
  endif()

  include(FindPackageHandleStandardArgs)
  find_package_handle_standard_args(LLBuild
    REQUIRED_VARS llbuild_FRAMEWORKS)
else()
  find_library(libllbuild_LIBRARIES libllbuild)
  find_file(libllbuild_INCLUDE_DIRS llbuild/llbuild.h)

  find_library(llbuildSwift_LIBRARIES llbuildSwift)
  find_file(llbuildSwift_INCLUDE_DIRS llbuildSwift.swiftmodule)

  include(FindPackageHandleStandardArgs)
  find_package_handle_standard_args(LLBuild REQUIRED_VARS
    libllbuild_LIBRARIES
    libllbuild_INCLUDE_DIRS
    llbuildSwift_LIBRARIES
    llbuildSwift_INCLUDE_DIRS)

  if(NOT TARGET libllbuild)
    add_library(libllbuild UNKNOWN IMPORTED)
    get_filename_component(libllbuild_INCLUDE_DIRS
      ${libllbuild_INCLUDE_DIRS} DIRECTORY)
    set_target_properties(libllbuild PROPERTIES
      INTERFACE_INCLUDE_DIRECTORIES ${libllbuild_INCLUDE_DIRS}
      IMPORTED_LOCATION ${libllbuild_LIBRARIES})
  endif()
  if(NOT TARGET llbuildSwift)
    add_library(llbuildSwift UNKNOWN IMPORTED)
    get_filename_component(llbuildSwift_INCLUDE_DIRS
      ${llbuildSwift_INCLUDE_DIRS} DIRECTORY)
    set_target_properties(llbuildSwift PROPERTIES
      INTERFACE_LINK_LIBRARIES libllbuild
      INTERFACE_INCLUDE_DIRECTORIES ${llbuildSwift_INCLUDE_DIRS}
      IMPORTED_LOCATION ${llbuildSwift_LIBRARIES})
  endif()
endif()
