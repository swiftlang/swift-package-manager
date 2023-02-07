# This source file is part of the Swift open source project
#
# Copyright (c) 2023 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(SPMLibzip STATIC)
target_include_directories(SPMLibzip INTERFACE
  ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(SPMLibzip INTERFACE
  libzip)
