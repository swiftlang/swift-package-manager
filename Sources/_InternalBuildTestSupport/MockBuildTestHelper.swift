//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics

@_spi(SwiftPMInternal)
import Build

import _InternalTestSupport
import struct PackageGraph.ModulesGraph
import struct PackageGraph.ResolvedModule
import struct PackageGraph.ResolvedProduct
import PackageModel
import SPMBuildCore
import TSCUtility
import XCTest

public func mockBuildPlan(
    buildPath: AbsolutePath? = nil,
    environment: BuildEnvironment,
    toolchain: PackageModel.Toolchain = MockToolchain(),
    graph: ModulesGraph,
    commonFlags: PackageModel.BuildFlags = .init(),
    indexStoreMode: BuildParameters.IndexStoreMode = .off,
    omitFramePointers: Bool? = nil,
    driverParameters: BuildParameters.Driver = .init(),
    linkingParameters: BuildParameters.Linking = .init(),
    targetSanitizers: EnabledSanitizers = .init(),
    fileSystem fs: any FileSystem,
    observabilityScope: ObservabilityScope
) async throws -> Build.BuildPlan {
    try await mockBuildPlan(
        buildPath: buildPath,
        config: environment.configuration ?? .debug,
        platform: environment.platform,
        toolchain: toolchain,
        graph: graph,
        commonFlags: commonFlags,
        indexStoreMode: indexStoreMode,
        omitFramePointers: omitFramePointers,
        driverParameters: driverParameters,
        linkingParameters: linkingParameters,
        targetSanitizers: targetSanitizers,
        fileSystem: fs,
        observabilityScope: observabilityScope
    )
}

public func mockBuildPlan(
    buildPath: AbsolutePath? = nil,
    config: BuildConfiguration = .debug,
    triple: Basics.Triple? = nil,
    platform: PackageModel.Platform? = nil,
    toolchain: PackageModel.Toolchain = MockToolchain(),
    graph: ModulesGraph,
    commonFlags: PackageModel.BuildFlags = .init(),
    indexStoreMode: BuildParameters.IndexStoreMode = .off,
    omitFramePointers: Bool? = nil,
    driverParameters: BuildParameters.Driver = .init(),
    linkingParameters: BuildParameters.Linking = .init(),
    targetSanitizers: EnabledSanitizers = .init(),
    fileSystem fs: any FileSystem,
    observabilityScope: ObservabilityScope
) async throws -> Build.BuildPlan {
    let inferredTriple: Basics.Triple
    if let platform {
        precondition(triple == nil)

        inferredTriple = switch platform {
        case .macOS:
            Triple.x86_64MacOS
        case .linux:
            Triple.arm64Linux
        case .android:
            Triple.arm64Android
        case .windows:
            Triple.windows
        default:
            fatalError("unsupported platform in tests")
        }
    } else {
        inferredTriple = triple ?? hostTriple
    }

    let commonDebuggingParameters = BuildParameters.Debugging(
        triple: inferredTriple,
        shouldEnableDebuggingEntitlement: config == .debug,
        omitFramePointers: omitFramePointers
    )

    var destinationParameters = mockBuildParameters(
        destination: .target,
        buildPath: buildPath,
        config: config,
        toolchain: toolchain,
        flags: commonFlags,
        triple: inferredTriple,
        indexStoreMode: indexStoreMode
    )
    destinationParameters.debuggingParameters = commonDebuggingParameters
    destinationParameters.driverParameters = driverParameters
    destinationParameters.linkingParameters = linkingParameters
    destinationParameters.sanitizers = targetSanitizers

    var hostParameters = mockBuildParameters(
        destination: .host,
        buildPath: buildPath,
        config: config,
        toolchain: toolchain,
        flags: commonFlags,
        triple: inferredTriple,
        indexStoreMode: indexStoreMode
    )
    hostParameters.debuggingParameters = commonDebuggingParameters
    hostParameters.driverParameters = driverParameters
    hostParameters.linkingParameters = linkingParameters

    return try await BuildPlan(
        destinationBuildParameters: destinationParameters,
        toolsBuildParameters: hostParameters,
        graph: graph,
        fileSystem: fs,
        observabilityScope: observabilityScope
    )
}

package func mockPluginTools(
    plugins: IdentifiableSet<ResolvedModule>,
    fileSystem: any FileSystem,
    buildParameters: BuildParameters,
    hostTriple: Basics.Triple
) async throws -> [ResolvedModule.ID: [String: PluginTool]] {
    var accessibleToolsPerPlugin: [ResolvedModule.ID: [String: PluginTool]] = [:]
    for plugin in plugins where accessibleToolsPerPlugin[plugin.id] == nil {
        let accessibleTools = try await plugin.preparePluginTools(
            fileSystem: fileSystem,
            environment: buildParameters.buildEnvironment,
            for: hostTriple
        ) { name, path in
            buildParameters.buildPath.appending(path)
        }

        accessibleToolsPerPlugin[plugin.id] = accessibleTools
    }

    return accessibleToolsPerPlugin
}

enum BuildError: Swift.Error {
    case error(String)
}

public struct BuildPlanResult {
    public let plan: Build.BuildPlan

    public var productMap: IdentifiableSet<Build.ProductBuildDescription> {
        self.plan.productMap
    }

    public var targetMap: IdentifiableSet<Build.ModuleBuildDescription> {
        self.plan.targetMap
    }

    public init(plan: Build.BuildPlan) throws {
        self.plan = plan
    }

    public func checkTargetsCount(_ count: Int, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(self.targetMap.count, count, file: file, line: line)
    }

    public func checkProductsCount(_ count: Int, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(self.productMap.count, count, file: file, line: line)
    }

    public func moduleBuildDescription(for name: String) throws -> Build.ModuleBuildDescription {
        let matches = self.targetMap.filter({ $0.module.name == name })
        guard matches.count == 1 else {
            if matches.isEmpty {
                throw BuildError.error("Target \(name) not found.")
            } else {
                throw BuildError.error("More than one target \(name) found.")
            }
        }
        return matches.first!
    }

    public func buildProduct(for name: String) throws -> Build.ProductBuildDescription {
        let matches = self.productMap.filter({ $0.product.name == name })
        guard matches.count == 1 else {
            if matches.isEmpty {
                // <rdar://problem/30162871> Display the thrown error on macOS
                throw BuildError.error("Product \(name) not found.")
            } else {
                throw BuildError.error("More than one target \(name) found.")
            }
        }
        return matches.first!
    }
}

extension Build.ModuleBuildDescription {
    public func swift() throws -> SwiftModuleBuildDescription {
        switch self {
        case .swift(let description):
            return description
        default:
            throw BuildError.error("Unexpected \(self) type found")
        }
    }

    public func clang() throws -> ClangModuleBuildDescription {
        switch self {
        case .clang(let description):
            return description
        default:
            throw BuildError.error("Unexpected \(self) type")
        }
    }
}
