# This source file is part of the Swift open source project
#
# Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(PackageModelSyntax
  AddPackageDependency.swift
  AddProduct.swift
  AddSwiftSetting.swift
  AddTarget.swift
  AddTargetDependency.swift
  ManifestEditError.swift
  ManifestSyntaxRepresentable.swift
  PackageDependency+Syntax.swift
  PackageEditResult.swift
  ProductDescription+Syntax.swift
  SyntaxEditUtils.swift
  TargetDescription+Syntax.swift
)

target_link_libraries(PackageModelSyntax PUBLIC
  Basics
  PackageLoading
  PackageModel

  SwiftSyntax::SwiftBasicFormat
  SwiftSyntax::SwiftDiagnostics
  SwiftSyntax::SwiftIDEUtils
  SwiftSyntax::SwiftParser
  SwiftSyntax::SwiftSyntax
  SwiftSyntax::SwiftSyntaxBuilder
)

# NOTE(compnerd) workaround for CMake not setting up include flags yet
set_target_properties(PackageModelSyntax PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

install(TARGETS PackageModelSyntax
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)
set_property(GLOBAL APPEND PROPERTY SwiftPM_EXPORTS PackageModelSyntax)
