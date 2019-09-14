# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

foreach(PACKAGE_DESCRIPTION_VERSION 4 4_2)
  add_library(PD${PACKAGE_DESCRIPTION_VERSION}
    BuildSettings.swift
    LanguageStandardSettings.swift
    Package.swift
    PackageDependency.swift
    PackageRequirement.swift
    Product.swift
    SupportedPlatforms.swift
    Target.swift
    Version+StringLiteralConvertible.swift
    Version.swift)
  target_compile_definitions(PD${PACKAGE_DESCRIPTION_VERSION} PRIVATE
    PACKAGE_DESCRIPTION_${PACKAGE_DESCRIPTION_VERSION})
  set_target_properties(PD${PACKAGE_DESCRIPTION_VERSION} PROPERTIES
    Swift_MODULE_NAME PackageDescription
    Swift_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/runtimes/${PACKAGE_DESCRIPTION_VERSION}
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/runtimes/${PACKAGE_DESCRIPTION_VERSION}
    OUTPUT_NAME PackageDescription
    ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/runtimes/${PACKAGE_DESCRIPTION_VERSION}
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/runtimes/${PACKAGE_DESCRIPTION_VERSION}
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/runtimes/${PACKAGE_DESCRIPTION_VERSION})
endforeach()

install(TARGETS PD4 PD4_2
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)
