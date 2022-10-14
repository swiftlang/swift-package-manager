# This source file is part of the Swift open source project
#
# Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(Basics
  Archiver.swift
  Archiver+Zip.swift
  AuthorizationProvider.swift
  ByteString+Extensions.swift
  Cancellator.swift
  ConcurrencyHelpers.swift
  Dictionary+Extensions.swift
  DispatchTimeInterval+Extensions.swift
  EnvironmentVariables.swift
  Errors.swift
  FileSystem+Extensions.swift
  HTPClient+URLSession.swift
  HTTPClient.swift
  JSON+Extensions.swift
  JSONDecoder+Extensions.swift
  Netrc.swift
  NSLock+Extensions.swift
  Observability.swift
  SQLite.swift
  Sandbox.swift
  String+Extensions.swift
  Triple+Extensions.swift
  SwiftVersion.swift
  SQLiteBackedCache.swift
  Version+Extensions.swift
  WritableByteStream+Extensions.swift)
target_link_libraries(Basics PUBLIC
  SwiftCollections::OrderedCollections
  SwiftSystem::SystemPackage
  TSCBasic
  TSCUtility)
target_link_libraries(Basics PRIVATE
  SPMSQLite3
  TSCclibc)
# NOTE(compnerd) workaround for CMake not setting up include flags yet
set_target_properties(Basics PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_options(Basics PRIVATE
    "$<$<PLATFORM_ID:Darwin>:SHELL:-Xlinker -framework -Xlinker Security>")

if(USE_CMAKE_INSTALL)
install(TARGETS Basics
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)
endif()
set_property(GLOBAL APPEND PROPERTY SwiftPM_EXPORTS Basics)
