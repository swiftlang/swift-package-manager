# This source file is part of the Swift open source project
#
# Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_compile_definitions(USE_IMPL_ONLY_IMPORTS)

add_subdirectory(_AsyncFileSystem)
add_subdirectory(Basics)
add_subdirectory(Build)
add_subdirectory(Commands)
add_subdirectory(CompilerPluginSupport)
add_subdirectory(CoreCommands)
add_subdirectory(DriverSupport)
add_subdirectory(LLBuildManifest)
add_subdirectory(PackageDescription)
add_subdirectory(PackageFingerprint)
add_subdirectory(PackageGraph)
add_subdirectory(PackageLoading)
add_subdirectory(PackageModel)
add_subdirectory(PackageModelSyntax)
add_subdirectory(PackagePlugin)
add_subdirectory(PackageRegistry)
add_subdirectory(PackageSigning)
add_subdirectory(SourceControl)
add_subdirectory(SourceKitLSPAPI)
add_subdirectory(SPMBuildCore)
add_subdirectory(SPMLLBuild)
add_subdirectory(SPMSQLite3)
add_subdirectory(swift-bootstrap)
add_subdirectory(swift-build)
add_subdirectory(swift-experimental-sdk)
add_subdirectory(swift-sdk)
add_subdirectory(swift-package)
add_subdirectory(swift-run)
add_subdirectory(swift-test)
add_subdirectory(SwiftSDKCommand)
add_subdirectory(Workspace)
add_subdirectory(XCBuildSupport)
add_subdirectory(SwiftBuildSupport)
