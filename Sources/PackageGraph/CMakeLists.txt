# This source file is part of the Swift open source project
#
# Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(PackageGraph
  BoundVersion.swift
  DependencyMirrors.swift
  DependencyResolutionNode.swift
  DependencyResolver.swift
  Diagnostics.swift
  GraphLoadingNode.swift
  ModuleAliasTracker.swift
  PackageContainer.swift
  PackageGraph.swift
  PackageGraph+Loading.swift
  PackageGraphRoot.swift
  PackageModel+Extensions.swift
  PackageRequirement.swift
  PinsStore.swift
  Pubgrub/Assignment.swift
  Pubgrub/Incompatibility.swift
  Pubgrub/PartialSolution.swift
  Pubgrub/PubgrubDependencyResolver.swift
  Pubgrub/Term.swift
  ResolvedPackage.swift
  ResolvedProduct.swift
  ResolvedTarget.swift
  Version+Extensions.swift
  VersionSetSpecifier.swift)
target_link_libraries(PackageGraph PUBLIC
  TSCBasic
  Basics
  PackageLoading
  PackageModel
  SourceControl
  TSCUtility)
# NOTE(compnerd) workaround for CMake not setting up include flags yet
set_target_properties(PackageGraph PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

if(USE_CMAKE_INSTALL)
install(TARGETS PackageGraph
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)
endif()
set_property(GLOBAL APPEND PROPERTY SwiftPM_EXPORTS PackageGraph)
