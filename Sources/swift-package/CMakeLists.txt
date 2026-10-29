# This source file is part of the Swift open source project
#
# Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_executable(swift-package
  Entrypoint.swift)
# TODO: Remove this once the minimum CMake version is 4.4.
set_target_properties(swift-package PROPERTIES
  Swift_MODULE_NAME swift_package)

target_link_libraries(swift-package PRIVATE
  Commands
  TSCBasic)

target_compile_options(swift-package PRIVATE
  -parse-as-library)

install(TARGETS swift-package
  RUNTIME DESTINATION bin)
