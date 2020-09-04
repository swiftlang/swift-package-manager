# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(TSCUtility
  Archiver.swift
  ArgumentParser.swift
  ArgumentParserShellCompletion.swift
  BuildFlags.swift
  CollectionExtensions.swift
  Diagnostics.swift
  Downloader.swift
  FSWatch.swift
  FloatingPointExtensions.swift
  Git.swift
  IndexStore.swift
  InterruptHandler.swift
  JSONMessageStreamingParser.swift
  misc.swift
  Netrc.swift
  OSLog.swift
  PersistenceCache.swift
  PkgConfig.swift
  Platform.swift
  PolymorphicCodable.swift
  ProgressAnimation.swift
  SQLite.swift
  SimplePersistence.swift
  StringExtensions.swift
  StringMangling.swift
  Triple.swift
  URL.swift
  Verbosity.swift
  Version.swift
  Versioning.swift
  dlopen.swift
  misc.swift
)
target_link_libraries(TSCUtility PUBLIC
  TSCBasic)
if(NOT CMAKE_SYSTEM_NAME STREQUAL Darwin)
  target_link_libraries(TSCUtility PRIVATE
    SQLite::SQLite3)
  target_link_libraries(TSCUtility PUBLIC
    FoundationNetworking)
endif()
# NOTE(compnerd) workaround for CMake not setting up include flags yet
set_target_properties(TSCUtility PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

if(USE_CMAKE_INSTALL)
  install(TARGETS TSCUtility
    ARCHIVE DESTINATION lib
    LIBRARY DESTINATION lib
    RUNTIME DESTINATION bin)
endif()

set_property(GLOBAL APPEND PROPERTY TSC_EXPORTS TSCUtility)
