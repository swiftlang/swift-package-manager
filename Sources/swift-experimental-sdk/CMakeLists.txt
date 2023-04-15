# This source file is part of the Swift open source project
#
# Copyright (c) 2023 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_executable(swift-experimental-sdk
  SwiftSDKTool.swift)
target_link_libraries(swift-experimental-sdk PRIVATE
  SwiftSDKTool)

target_compile_options(swift-experimental-sdk PRIVATE
  -parse-as-library)

if(USE_CMAKE_INSTALL)
install(TARGETS swift-experimental-sdk
  RUNTIME DESTINATION bin)
endif()
