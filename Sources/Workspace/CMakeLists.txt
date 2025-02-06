# This source file is part of the Swift open source project
#
# Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(Workspace
  CheckoutState.swift
  Diagnostics.swift
  InitPackage.swift
  LoadableResult.swift
  ManagedArtifact.swift
  ManagedDependency.swift
  ManagedPrebuilt.swift
  PackageContainer/FileSystemPackageContainer.swift
  PackageContainer/RegistryPackageContainer.swift
  PackageContainer/SourceControlPackageContainer.swift
  ResolvedFileWatcher.swift
  ResolverPrecomputationProvider.swift
  ToolsVersionSpecificationRewriter.swift
  Workspace.swift
  Workspace+BinaryArtifacts.swift
  Workspace+Configuration.swift
  Workspace+Delegation.swift
  Workspace+Dependencies.swift
  Workspace+Editing.swift
  Workspace+Manifests.swift
  Workspace+PackageContainer.swift
  Workspace+Prebuilts.swift
  Workspace+Registry.swift
  Workspace+ResolvedPackages.swift
  Workspace+Signing.swift
  Workspace+SourceControl.swift
  Workspace+State.swift)
target_link_libraries(Workspace PUBLIC
  TSCBasic
  TSCUtility
  Basics
  SPMBuildCore
  SwiftCollections::OrderedCollections
  PackageFingerprint
  PackageGraph
  PackageLoading
  PackageModel
  PackageRegistry
  PackageSigning
  SourceControl)
target_link_libraries(Workspace PUBLIC
  $<$<NOT:$<PLATFORM_ID:Darwin>>:Foundation>)
# NOTE(compnerd) workaround for CMake not setting up include flags yet
set_target_properties(Workspace PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

install(TARGETS Workspace
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)
