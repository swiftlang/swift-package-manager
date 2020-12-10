# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(Basics
  ConcurrencyHelpers.swift
  Dictionary+Extensions.swift
  DispatchTimeInterval+Extensions.swift
  Errors.swift
  FileSystem+Extensions.swift
  HTPClient+URLSession.swift
  HTTPClient.swift
  JSON+Extensions.swift)
target_link_libraries(Basics PUBLIC
  TSCBasic
  TSCUtility)
# NOTE(compnerd) workaround for CMake not setting up include flags yet
set_target_properties(Basics PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

if(USE_CMAKE_INSTALL)
install(TARGETS Basics
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)
endif()
set_property(GLOBAL APPEND PROPERTY SwiftPM_EXPORTS Basics)
