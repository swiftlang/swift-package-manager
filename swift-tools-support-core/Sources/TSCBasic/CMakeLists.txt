# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(TSCBasic
  Await.swift
  ByteString.swift
  CStringArray.swift
  CacheableSequence.swift
  CodableResult.swift
  CollectionAlgorithms.swift
  CollectionExtensions.swift
  Condition.swift
  DeltaAlgorithm.swift
  DiagnosticsEngine.swift
  DictionaryExtensions.swift
  DictionaryLiteralExtensions.swift
  EditDistance.swift
  FileInfo.swift
  FileSystem.swift
  GraphAlgorithms.swift
  HashAlgorithms.swift
  JSON.swift
  JSONMapper.swift
  KeyedPair.swift
  LazyCache.swift
  Lock.swift
  OSLog.swift
  ObjectIdentifierProtocol.swift
  OrderedDictionary.swift
  OrderedSet.swift
  OutputByteStream.swift
  Path.swift
  PathShims.swift
  Process.swift
  ProcessEnv.swift
  ProcessSet.swift
  RegEx.swift
  Result.swift
  SortedArray.swift
  StringConversions.swift
  SynchronizedQueue.swift
  TemporaryFile.swift
  TerminalController.swift
  Thread.swift
  Tuple.swift
  misc.swift)
target_compile_options(TSCBasic PUBLIC
  # Don't use GNU strerror_r on Android.
  "$<$<PLATFORM_ID:Android>:SHELL:-Xcc -U_GNU_SOURCE>"
  # Ignore secure function warnings on Windows.
  "$<$<PLATFORM_ID:Windows>:SHELL:-Xcc -D_CRT_SECURE_NO_WARNINGS>")
target_link_libraries(TSCBasic PUBLIC
  TSCLibc)
if(NOT CMAKE_SYSTEM_NAME STREQUAL Darwin)
  target_link_libraries(TSCBasic PUBLIC
    Foundation)
endif()
# NOTE(compnerd) workaround for CMake not setting up include flags yet
set_target_properties(TSCBasic PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})


if(USE_CMAKE_INSTALL)
install(TARGETS TSCBasic
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)
endif()

set_property(GLOBAL APPEND PROPERTY TSC_EXPORTS TSCBasic)
