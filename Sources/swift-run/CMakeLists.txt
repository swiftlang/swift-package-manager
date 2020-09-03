# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_executable(swift-run
  main.swift)
target_link_libraries(swift-run PRIVATE
  Commands)

if(USE_CMAKE_INSTALL)
install(TARGETS swift-run
  RUNTIME DESTINATION bin)
endif()
