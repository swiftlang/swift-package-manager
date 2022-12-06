//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Build
import SPMBuildCore
import XCBuildSupport

import class Basics.ObservabilityScope
import struct PackageGraph.PackageGraph
import struct PackageLoading.FileRuleDescription
import protocol TSCBasic.OutputByteStream

extension SwiftTool {
    public var defaultBuildSystemProvider: BuildSystemProvider {
        get throws {
            return .init(providers: [
                .native: { (explicitProduct: String?, cacheBuildManifest: Bool, customBuildParameters: BuildParameters?, customPackageGraphLoader: (() throws -> PackageGraph)?, customOutputStream: OutputByteStream?, customLogLevel: Diagnostic.Severity?, customObservabilityScope: ObservabilityScope?) throws -> BuildSystem in
                    let testEntryPointPath = customBuildParameters?.testProductStyle.explicitlySpecifiedEntryPointPath
                    let graphLoader = { try self.loadPackageGraph(explicitProduct: explicitProduct, testEntryPointPath: testEntryPointPath) }
                    return try BuildOperation(
                        buildParameters: customBuildParameters ?? self.buildParameters(),
                        cacheBuildManifest: cacheBuildManifest && self.canUseCachedBuildManifest(),
                        packageGraphLoader: customPackageGraphLoader ?? graphLoader,
                        additionalFileRules: FileRuleDescription.swiftpmFileTypes,
                        pluginScriptRunner: self.getPluginScriptRunner(),
                        pluginWorkDirectory: try self.getActiveWorkspace().location.pluginWorkingDirectory,
                        pkgConfigDirectory: self.options.locations.pkgConfigDirectory,
                        disableSandboxForPluginCommands: self.options.security.shouldDisableSandbox,
                        outputStream: customOutputStream ?? self.outputStream,
                        logLevel: customLogLevel ?? self.logLevel,
                        fileSystem: self.fileSystem,
                        observabilityScope: customObservabilityScope ?? self.observabilityScope)
                },
                .xcode: { (explicitProduct: String?, cacheBuildManifest: Bool, customBuildParameters: BuildParameters?, customPackageGraphLoader: (() throws -> PackageGraph)?, customOutputStream: OutputByteStream?, customLogLevel: Diagnostic.Severity?, customObservabilityScope: ObservabilityScope?) throws -> BuildSystem in
                    let graphLoader = { try self.loadPackageGraph(explicitProduct: explicitProduct) }
                    return try XcodeBuildSystem(
                        buildParameters: customBuildParameters ?? self.buildParameters(),
                        packageGraphLoader: customPackageGraphLoader ?? graphLoader,
                        outputStream: customOutputStream ?? self.outputStream,
                        logLevel: customLogLevel ?? self.logLevel,
                        fileSystem: self.fileSystem,
                        observabilityScope: customObservabilityScope ?? self.observabilityScope
                    )
                },
            ])
        }
    }
}
