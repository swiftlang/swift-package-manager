# This source file is part of the Swift.org open source project
#
# Copyright (c) 2021 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(PackagePlugin
    PublicAPI/CommandConstructor.swift
    PublicAPI/DiagnosticsEmitter.swift
    PublicAPI/Globals.swift
    PublicAPI/Path.swift
    PublicAPI/TargetBuildContext.swift
    ImplementationDetails.swift)
  
if(CMAKE_HOST_SYSTEM_NAME STREQUAL Darwin)
    set(SWIFT_INTERFACE_PATH ${CMAKE_BINARY_DIR}/pm/PackagePlugin.swiftinterface)
    target_compile_options(PackagePlugin PUBLIC
        $<$<COMPILE_LANGUAGE:Swift>:-enable-library-evolution>)
    target_compile_options(PackagePlugin PUBLIC
        $<$<COMPILE_LANGUAGE:Swift>:-emit-module-interface-path$<SEMICOLON>${SWIFT_INTERFACE_PATH}>)
    target_link_options(PackagePlugin PRIVATE
        "SHELL:-Xlinker -install_name -Xlinker @rpath/libPackagePlugin.dylib")
endif()

set_target_properties(PackagePlugin PROPERTIES
    Swift_MODULE_NAME PackagePlugin
    Swift_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/pm
    INSTALL_NAME_DIR \\@rpath
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm
    OUTPUT_NAME PackagePlugin
    ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/pm
)

if(NOT CMAKE_SYSTEM_NAME STREQUAL Darwin)
    if(Foundation_FOUND)
        target_link_libraries(PackagePlugin PRIVATE
            Foundation)
    endif()
    target_link_options(PackagePlugin PRIVATE
        "SHELL:-no-toolchain-stdlib-rpath")
    set_target_properties(PackagePlugin PROPERTIES
        BUILD_WITH_INSTALL_RPATH TRUE
        INSTALL_RPATH "$ORIGIN/../../$<LOWER_CASE:${CMAKE_SYSTEM_NAME}>")
endif()

if(CMAKE_HOST_SYSTEM_NAME STREQUAL Darwin)
    install(FILES
        ${CMAKE_BINARY_DIR}/pm/PackagePlugin.swiftinterface
        ${CMAKE_BINARY_DIR}/pm/PackagePlugin.swiftdoc
        DESTINATION lib/swift/pm
    )
else()
    install(FILES
        ${CMAKE_BINARY_DIR}/pm/PackagePlugin.swiftmodule
        ${CMAKE_BINARY_DIR}/pm/PackagePlugin.swiftdoc
        DESTINATION lib/swift/pm
    )
endif()

install(TARGETS PackagePlugin
    DESTINATION lib/swift/pm)
