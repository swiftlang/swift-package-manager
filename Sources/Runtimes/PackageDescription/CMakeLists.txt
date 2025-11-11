# This source file is part of the Swift open source project
#
# Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(PackageDescription
  BuildSettings.swift
  Context.swift
  ContextModel.swift
  LanguageStandardSettings.swift
  PackageDescription.swift
  PackageDescriptionSerialization.swift
  PackageDescriptionSerializationConversion.swift
  PackageDependency.swift
  PackageDependencyTrait.swift
  PackageRequirement.swift
  Product.swift
  Resource.swift
  SupportedPlatforms.swift
  Target.swift
  Trait.swift
  Version.swift
  Version+StringLiteralConvertible.swift
  WarningLevel.swift)

set_target_properties(PackageDescription PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_CURRENT_BINARY_DIR})
target_compile_definitions(PackageDescription PRIVATE
  USE_IMPL_ONLY_IMPORTS)

if(APPLE)
  target_link_options(PackageDescription PRIVATE
    "SHELL:-Xlinker -install_name -Xlinker @rpath/libPackageDescription.dylib")
else()
  target_link_libraries(PackageDescription PRIVATE
    Foundation)
endif()

install(TARGETS PackageDescription
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/swift/pm/ManifestAPI)

set(SwiftPMRuntime_INSTALL_SWIFTMODULEDIR
  ${CMAKE_INSTALL_LIBDIR}/swift/pm/ManifestAPI)
emit_swift_interface(PackageDescription)
install_swift_interface(PackageDescription)
