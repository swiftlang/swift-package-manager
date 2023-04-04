# This source file is part of the Swift open source project
#
# Copyright (c) 2023 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(CrossCompilationDestinationsTool
  Configuration/ConfigurationCommand.swift
  Configuration/ConfigureDestination.swift
  Configuration/ResetConfiguration.swift
  Configuration/SetConfiguration.swift
  Configuration/ShowConfiguration.swift
  DestinationCommand.swift
  InstallDestination.swift
  ListDestinations.swift
  RemoveDestination.swift
  SwiftDestinationTool.swift)
target_link_libraries(CrossCompilationDestinationsTool PUBLIC
  ArgumentParser
  Basics
  CoreCommands
  SPMBuildCore
  PackageModel)
# NOTE(compnerd) workaround for CMake not setting up include flags yet
set_target_properties(CrossCompilationDestinationsTool PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

target_compile_options(CrossCompilationDestinationsTool PRIVATE
  -Xfrontend -validate-tbd-against-ir=none)

if(USE_CMAKE_INSTALL)
install(TARGETS CrossCompilationDestinationsTool
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)
endif()
