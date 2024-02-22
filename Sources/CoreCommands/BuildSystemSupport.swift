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

#if !SKIP_XCBUILD_SUPPORT
import XCBuildSupport
#endif

import class Basics.ObservabilityScope
import struct PackageGraph.PackageGraph
import struct PackageLoading.FileRuleDescription
import protocol TSCBasic.OutputByteStream

private struct NativeBuildSystemFactory: BuildSystemFactory {
    let swiftTool: SwiftTool

    func makeBuildSystem(
        explicitProduct: String?,
        cacheBuildManifest: Bool,
        productsBuildParameters: BuildParameters?,
        toolsBuildParameters: BuildParameters?,
        packageGraphLoader: (() throws -> PackageGraph)?,
        outputStream: OutputByteStream?,
        logLevel: Diagnostic.Severity?,
        observabilityScope: ObservabilityScope?
    ) throws -> any BuildSystem {
        let rootPackageInfo = try swiftTool.getRootPackageInformation()
        let testEntryPointPath = productsBuildParameters?.testingParameters.testProductStyle.explicitlySpecifiedEntryPointPath
        return try BuildOperation(
            productsBuildParameters: try productsBuildParameters ?? self.swiftTool.productsBuildParameters,
            toolsBuildParameters: try toolsBuildParameters ?? self.swiftTool.toolsBuildParameters,
            cacheBuildManifest: cacheBuildManifest && self.swiftTool.canUseCachedBuildManifest(),
            packageGraphLoader: packageGraphLoader ?? {
                try self.swiftTool.loadPackageGraph(
                    explicitProduct: explicitProduct,
                    testEntryPointPath: testEntryPointPath
                )
            },
            pluginConfiguration: .init(
                scriptRunner: self.swiftTool.getPluginScriptRunner(),
                workDirectory: try self.swiftTool.getActiveWorkspace().location.pluginWorkingDirectory,
                disableSandbox: self.swiftTool.shouldDisableSandbox
            ),
            additionalFileRules: FileRuleDescription.swiftpmFileTypes,
            pkgConfigDirectories: self.swiftTool.options.locations.pkgConfigDirectories,
            dependenciesByRootPackageIdentity: rootPackageInfo.dependecies,
            targetsByRootPackageIdentity: rootPackageInfo.targets,
            outputStream: outputStream ?? self.swiftTool.outputStream,
            logLevel: logLevel ?? self.swiftTool.logLevel,
            fileSystem: self.swiftTool.fileSystem,
            observabilityScope: observabilityScope ?? self.swiftTool.observabilityScope)
    }
}

#if !SKIP_XCBUILD_SUPPORT
private struct XcodeBuildSystemFactory: BuildSystemFactory {
    let swiftTool: SwiftTool

    func makeBuildSystem(
        explicitProduct: String?,
        cacheBuildManifest: Bool,
        productsBuildParameters: BuildParameters?,
        toolsBuildParameters: BuildParameters?,
        packageGraphLoader: (() throws -> PackageGraph)?,
        outputStream: OutputByteStream?,
        logLevel: Diagnostic.Severity?,
        observabilityScope: ObservabilityScope?
    ) throws -> any BuildSystem {
        return try XcodeBuildSystem(
            buildParameters: productsBuildParameters ?? self.swiftTool.productsBuildParameters,
            packageGraphLoader: packageGraphLoader ?? {
                try self.swiftTool.loadPackageGraph(
                    explicitProduct: explicitProduct
                )
            },
            outputStream: outputStream ?? self.swiftTool.outputStream,
            logLevel: logLevel ?? self.swiftTool.logLevel,
            fileSystem: self.swiftTool.fileSystem,
            observabilityScope: observabilityScope ?? self.swiftTool.observabilityScope
        )
    }
}
#endif

extension SwiftTool {
    public var defaultBuildSystemProvider: BuildSystemProvider {
        #if !SKIP_XCBUILD_SUPPORT
        .init(providers: [
            .native: NativeBuildSystemFactory(swiftTool: self),
            .xcode: XcodeBuildSystemFactory(swiftTool: self)
        ])
        #else
        .init(providers: [
            .native: NativeBuildSystemFactory(swiftTool: self),
        ])
        #endif
    }
}
