# This source file is part of the Swift open source project
#
# Copyright (c) 2026 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(PackageAudit STATIC
  OSVRecord.swift
  OSVRecord+Ranges.swift
  AdvisorySeverity.swift
  CVSSv3.swift
  SwiftURLName.swift
  AdvisoryDatabase.swift
  OSVAPIDatabase.swift
  OSVLocalDatabase.swift)
target_link_libraries(PackageAudit PUBLIC
  TSCBasic
  TSCUtility
  Basics
  PackageGraph
  PackageModel)

# NOTE(compnerd) workaround for CMake not setting up include flags yet
set_target_properties(PackageAudit PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
