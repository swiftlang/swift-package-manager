# This source file is part of the Swift open source project
#
# Copyright (c) 2023 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(SwiftSDKCommand
  Configuration/ConfigurationSubcommand.swift
  Configuration/DeprecatedSwiftSDKConfigurationCommand.swift
  Configuration/ResetConfiguration.swift
  Configuration/SetConfiguration.swift
  Configuration/ShowConfiguration.swift
  ConfigureSwiftSDK.swift
  SwiftSDKSubcommand.swift
  InstallSwiftSDK.swift
  ListSwiftSDKs.swift
  RemoveSwiftSDK.swift
  SwiftSDKCommand.swift)
target_link_libraries(SwiftSDKCommand PUBLIC
  ArgumentParser
  Basics
  CoreCommands
  SPMBuildCore
  PackageModel)
# NOTE(compnerd) workaround for CMake not setting up include flags yet
set_target_properties(SwiftSDKCommand PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

install(TARGETS SwiftSDKCommand
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)
