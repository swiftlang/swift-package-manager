# This source file is part of the Swift open source project
#
# Copyright (c) 2023-2025 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(CompilerPluginSupport
  TargetExtensions.swift)
target_link_libraries(CompilerPluginSupport PRIVATE
  PackageDescription)

if(APPLE)
  target_link_options(CompilerPluginSupport PRIVATE
    "SHELL:-Xlinker -install_name -Xlinker @rpath/CompilerPluginSupport.dylib")
else()
  target_link_libraries(CompilerPluginSupport PRIVATE
    Foundation)
endif()

install(TARGETS CompilerPluginSupport
  DESTINATION ${CMAKE_INSTALL_LIBDIR}/swift/pm/ManifestAPI)

set(SwiftPMRuntime_INSTALL_SWIFTMODULEDIR
  ${CMAKE_INSTALL_LIBDIR}/swift/pm/ManifestAPI)
emit_swift_interface(CompilerPluginSupport)
install_swift_interface(CompilerPluginSupport)
