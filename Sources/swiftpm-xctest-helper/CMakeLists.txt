# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_executable(swiftpm-xctest-helper
  main.swift)

if(CMAKE_HOST_SYSTEM_NAME STREQUAL Darwin)
  target_link_options(swiftpm-xctest-helper PRIVATE
    "-Xlinker -rpath -Xlinker @executable_path/../../../lib/swift/macosx")
endif()

install(TARGETS swiftpm-xctest-helper
  RUNTIME DESTINATION bin)
