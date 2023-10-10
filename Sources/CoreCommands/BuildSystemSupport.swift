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

private struct NativeBuildSystemFactory: BuildSystemFactory {
    let swiftTool: SwiftTool

    func makeBuildSystem(
        explicitProduct: String?,
        cacheBuildManifest: Bool,
        customBuildParameters: BuildParameters?,
        customPackageGraphLoader: (() throws -> PackageGraph)?,
        customOutputStream: OutputByteStream?,
        customLogLevel: Diagnostic.Severity?,
        customObservabilityScope: ObservabilityScope?
    ) throws -> any BuildSystem {
        let testEntryPointPath = customBuildParameters?.testingParameters.testProductStyle.explicitlySpecifiedEntryPointPath
        let graphLoader = { try self.swiftTool.loadPackageGraph(explicitProduct: explicitProduct, testEntryPointPath: testEntryPointPath) }
        return try BuildOperation(
            buildParameters: customBuildParameters ?? self.swiftTool.buildParameters(),
            cacheBuildManifest: cacheBuildManifest && self.swiftTool.canUseCachedBuildManifest(),
            packageGraphLoader: customPackageGraphLoader ?? graphLoader,
            pluginConfiguration: .init(
                scriptRunner: self.swiftTool.getPluginScriptRunner(),
                workDirectory: try self.swiftTool.getActiveWorkspace().location.pluginWorkingDirectory,
                disableSandbox: self.swiftTool.shouldDisableSandbox
            ),
            additionalFileRules: FileRuleDescription.swiftpmFileTypes,
            pkgConfigDirectories: self.swiftTool.options.locations.pkgConfigDirectories,
            outputStream: customOutputStream ?? self.swiftTool.outputStream,
            logLevel: customLogLevel ?? self.swiftTool.logLevel,
            fileSystem: self.swiftTool.fileSystem,
            observabilityScope: customObservabilityScope ?? self.swiftTool.observabilityScope)
    }
}

private struct XcodeBuildSystemFactory: BuildSystemFactory {
    let swiftTool: SwiftTool

    func makeBuildSystem(
        explicitProduct: String?,
        cacheBuildManifest: Bool,
        customBuildParameters: BuildParameters?,
        customPackageGraphLoader: (() throws -> PackageGraph)?,
        customOutputStream: OutputByteStream?,
        customLogLevel: Diagnostic.Severity?,
        customObservabilityScope: ObservabilityScope?
    ) throws -> any BuildSystem {
        let graphLoader = { try self.swiftTool.loadPackageGraph(explicitProduct: explicitProduct) }
        return try XcodeBuildSystem(
            buildParameters: customBuildParameters ?? self.swiftTool.buildParameters(),
            packageGraphLoader: customPackageGraphLoader ?? graphLoader,
            outputStream: customOutputStream ?? self.swiftTool.outputStream,
            logLevel: customLogLevel ?? self.swiftTool.logLevel,
            fileSystem: self.swiftTool.fileSystem,
            observabilityScope: customObservabilityScope ?? self.swiftTool.observabilityScope
        )
    }
}

extension SwiftTool {
    public var defaultBuildSystemProvider: BuildSystemProvider {
        .init(providers: [
            .native: NativeBuildSystemFactory(swiftTool: self),
            .xcode: XcodeBuildSystemFactory(swiftTool: self)
        ])
    }
}
