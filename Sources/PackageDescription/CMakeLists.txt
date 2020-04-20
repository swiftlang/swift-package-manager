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
        PackageDescription.swift
        PackageDependency.swift
        PackageRequirement.swift
        Product.swift
        Resource.swift
        SupportedPlatforms.swift
        Target.swift
        Version.swift
        Version+StringLiteralConvertible.swift)

    target_compile_definitions(PD${PACKAGE_DESCRIPTION_VERSION} PRIVATE
        PACKAGE_DESCRIPTION_${PACKAGE_DESCRIPTION_VERSION})

    if(CMAKE_HOST_SYSTEM_NAME STREQUAL Darwin)
        set(SWIFT_INTERFACE_PATH ${CMAKE_BINARY_DIR}/pm/${PACKAGE_DESCRIPTION_VERSION}/PackageDescription.swiftinterface)
        target_compile_options(PD${PACKAGE_DESCRIPTION_VERSION} PUBLIC
            $<$<COMPILE_LANGUAGE:Swift>:-enable-library-evolution>)
        target_compile_options(PD${PACKAGE_DESCRIPTION_VERSION} PUBLIC
            $<$<COMPILE_LANGUAGE:Swift>:-emit-module-interface-path$<SEMICOLON>${SWIFT_INTERFACE_PATH}>)
        target_link_options(PD${PACKAGE_DESCRIPTION_VERSION} PRIVATE
            "SHELL:-Xlinker -install_name -Xlinker @rpath/libPackageDescription.dylib")
    endif()

    set_target_properties(PD${PACKAGE_DESCRIPTION_VERSION} PROPERTIES
        Swift_MODULE_NAME PackageDescription
        Swift_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/pm/${PACKAGE_DESCRIPTION_VERSION}
        INSTALL_NAME_DIR \\@rpath
        OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/${PACKAGE_DESCRIPTION_VERSION}
        OUTPUT_NAME PackageDescription
        ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/${PACKAGE_DESCRIPTION_VERSION}
        LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/${PACKAGE_DESCRIPTION_VERSION}
        RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm/${PACKAGE_DESCRIPTION_VERSION}
    )

    if(NOT CMAKE_SYSTEM_NAME STREQUAL Darwin)
      target_link_libraries(PD${PACKAGE_DESCRIPTION_VERSION} PRIVATE
        Foundation)
      target_link_options(PD${PACKAGE_DESCRIPTION_VERSION} PRIVATE
        "SHELL:-no-toolchain-stdlib-rpath")
      set_target_properties(PD${PACKAGE_DESCRIPTION_VERSION} PROPERTIES
          BUILD_WITH_INSTALL_RPATH TRUE
          INSTALL_RPATH "$ORIGIN/../../$<LOWER_CASE:${CMAKE_SYSTEM_NAME}>")
    endif()

    if(CMAKE_HOST_SYSTEM_NAME STREQUAL Darwin)
        install(FILES
            ${CMAKE_BINARY_DIR}/pm/${PACKAGE_DESCRIPTION_VERSION}/PackageDescription.swiftinterface
            DESTINATION lib/swift/pm/${PACKAGE_DESCRIPTION_VERSION}
        )
    else()
        install(FILES
            ${CMAKE_BINARY_DIR}/pm/${PACKAGE_DESCRIPTION_VERSION}/PackageDescription.swiftmodule
            ${CMAKE_BINARY_DIR}/pm/${PACKAGE_DESCRIPTION_VERSION}/PackageDescription.swiftdoc
            DESTINATION lib/swift/pm/${PACKAGE_DESCRIPTION_VERSION}
        )
    endif()

    install(TARGETS PD${PACKAGE_DESCRIPTION_VERSION}
      DESTINATION lib/swift/pm/${PACKAGE_DESCRIPTION_VERSION})
endforeach()
