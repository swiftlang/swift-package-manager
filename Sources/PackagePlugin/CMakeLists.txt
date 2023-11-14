# This source file is part of the Swift open source project
#
# Copyright (c) 2021-2022 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(PackagePlugin STATIC
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
target_compile_options(PackagePlugin PRIVATE
  $<$<COMPILE_LANGUAGE:Swift>:-package-description-version$<SEMICOLON>999.0>
  $<$<COMPILE_LANGUAGE:Swift>:-enable-library-evolution>)
set_target_properties(PackagePlugin PROPERTIES
  Swift_MODULE_NAME PackagePlugin
  Swift_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/pm/PluginAPI
  OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/PluginAPI
  ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/PluginAPI
  LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/PluginAPI
  RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/PluginAPI)

if(CMAKE_HOST_SYSTEM_NAME STREQUAL Darwin)
  set(SWIFT_INTERFACE_PATH ${CMAKE_BINARY_DIR}/pm/PluginAPI/PackagePlugin.swiftinterface)
  target_compile_options(PackagePlugin PRIVATE
    $<$<COMPILE_LANGUAGE:Swift>:-emit-module-interface-path$<SEMICOLON>${SWIFT_INTERFACE_PATH}>)
endif()

install(FILES
  ${CMAKE_BINARY_DIR}/pm/PluginAPI/PackagePlugin.swift$<IF:$<PLATFORM_ID:Darwin>,interface,module>
  ${CMAKE_BINARY_DIR}/pm/PluginAPI/PackagePlugin.swiftdoc
  DESTINATION lib/swift/pm/PluginAPI)
install(TARGETS PackagePlugin
  DESTINATION lib/swift/pm/PluginAPI)
