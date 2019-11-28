# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(TSCUtility
  ArgumentParser.swift
  ArgumentParserShellCompletion.swift
  BuildFlags.swift
  CollectionExtensions.swift
  Diagnostics.swift
  dlopen.swift
  FSWatch.swift
  Git.swift
  IndexStore.swift
  InterruptHandler.swift
  misc.swift
  OSLog.swift
  PkgConfig.swift
  Platform.swift
  ProgressAnimation.swift
  SimplePersistence.swift
  StringExtensions.swift
  StringMangling.swift
  URL.swift
  Verbosity.swift
  Version.swift
  Versioning.swift)
target_link_libraries(TSCUtility PUBLIC
  TSCBasic)
# NOTE(compnerd) workaround for CMake not setting up include flags yet
set_target_properties(TSCUtility PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

if(BUILD_SHARED_LIBS)
  get_swift_host_arch(swift_arch)
  install(TARGETS TSCUtility
    ARCHIVE DESTINATION lib/swift/pm
    LIBRARY DESTINATION lib/swift/pm
    RUNTIME DESTINATION bin)
endif()
