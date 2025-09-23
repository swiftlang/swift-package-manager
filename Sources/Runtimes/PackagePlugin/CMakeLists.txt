# This source file is part of the Swift open source project
#
# Copyright (c) 2021-2025 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(PackagePlugin
  ArgumentExtractor.swift
  Command.swift
  Context.swift
  Diagnostics.swift
  Errors.swift
  PackageManagerProxy.swift
  PackageModel.swift
  Path.swift
  Plugin.swift
  PluginContextDeserializer.swift
  PluginMessages.swift
  Protocols.swift
  Utilities.swift)

if(APPLE)
  target_link_options(PackagePlugin PRIVATE
    "SHELL:-Xlinker -install_name -Xlinker @rpath/libPackagePlugin.dylib")
else()
  target_link_libraries(PackagePlugin PRIVATE
    Foundation)
endif()

install(TARGETS PackagePlugin
  DESTINATION ${CMAKE_INSTALL_LIBDIR}/swift/pm/PluginAPI)

set(SwiftPMRuntime_INSTALL_SWIFTMODULEDIR
  ${CMAKE_INSTALL_LIBDIR}/swift/pm/PluginAPI)
emit_swift_interface(PackagePlugin)
install_swift_interface(PackagePlugin)
