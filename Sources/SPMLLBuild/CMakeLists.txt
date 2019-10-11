# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

# LLBuild currently doesn't export the llbuildSwift target so import it manually for now.
add_library(libllbuildSwift SHARED IMPORTED GLOBAL)
set(LLBUILD_BUILD_DIR ${LLBuild_DIR}/../..)
set_target_properties(libllbuildSwift
   PROPERTIES
   IMPORTED_LOCATION ${LLBUILD_BUILD_DIR}/lib/libllbuildSwift.dylib
   INTERFACE_INCLUDE_DIRECTORIES ${LLBUILD_BUILD_DIR}/products/llbuildSwift)

add_library(SPMLLBuild
  llbuild.swift)

target_link_libraries(SPMLLBuild PUBLIC
  TSCBasic
  TSCUtility
  libllbuild
  libllbuildSwift
)

# NOTE(compnerd) workaround for CMake not setting up include flags yet
set_target_properties(SPMLLBuild PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

install(TARGETS SPMLLBuild
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)
