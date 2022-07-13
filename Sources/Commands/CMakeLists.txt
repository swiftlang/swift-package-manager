# This source file is part of the Swift open source project
#
# Copyright (c) 2014 - 2022 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(Commands

  Options.swift
  Snippets/CardEvent.swift
  Snippets/Cards/SnippetCard.swift
  Snippets/Cards/SnippetGroupCard.swift
  Snippets/Cards/TopCard.swift
  Snippets/CardStack.swift
  Snippets/Card.swift
  Snippets/Colorful.swift
  SwiftBuildTool.swift
  SwiftPackageCollectionsTool.swift
  SwiftPackageRegistryTool.swift
  SwiftPackageTool.swift
  SwiftRunTool.swift
  SwiftTestTool.swift
  SwiftTool.swift
  Utilities/APIDigester.swift
  Utilities/DependenciesSerializer.swift
  Utilities/Describe.swift
  Utilities/DOTManifestSerializer.swift
  Utilities/GenerateLinuxMain.swift
  Utilities/MultiRootSupport.swift
  Utilities/SymbolGraphExtract.swift
  Utilities/TestingSupport.swift
  Utilities/WatchmanHelper.swift)
target_link_libraries(Commands PUBLIC
  ArgumentParser
  Basics
  Build
  PackageCollections
  PackageFingerprint
  PackageGraph
  SourceControl
  TSCBasic
  TSCUtility
  Workspace
  XCBuildSupport
  Xcodeproj)
target_link_libraries(Commands PRIVATE
  $<$<NOT:$<PLATFORM_ID:Darwin>>:FoundationXML>)
# NOTE(compnerd) workaround for CMake not setting up include flags yet
set_target_properties(Commands PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

if(USE_CMAKE_INSTALL)
install(TARGETS Commands
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)
endif()
