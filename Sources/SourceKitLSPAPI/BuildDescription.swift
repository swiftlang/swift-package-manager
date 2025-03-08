//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import TSCBasic

// Ideally wouldn't expose these (it defeats the purpose of this module), but we should replace this entire API with
// a BSP server, so this is good enough for now (and LSP is using all these types internally anyway).
import Basics
import Build
import PackageGraph
internal import PackageLoading
internal import PackageModel
import SPMBuildCore

public enum BuildDestination {
    case host
    case target
}

public enum BuildTargetCompiler {
    case swift
    case clang
}

/// Information about a source file that belongs to a target.
public struct SourceItem {
    /// The URL of the source file itself.
    public let sourceFile: URL

    /// If the file has a unique output path (eg. for clang files), the output paths. `nil` for eg. Swift targets,
    /// which don't have unique output paths for each file.
    public let outputFile: URL?
}

public protocol BuildTarget {
    /// Source files in the target
    var sources: [SourceItem] { get }

    /// Header files in the target
    var headers: [URL] { get }

    /// The resource files in the target.
    var resources: [URL] { get }

    /// Files in the target that were marked as ignored.
    var ignored: [URL] { get }

    /// Other kinds of files in the target.
    var others: [URL] { get }

    /// The name of the target. It should be possible to build a target by passing this name to `swift build --target`
    var name: String { get }

    /// The compiler that is responsible for building this target.
    var compiler: BuildTargetCompiler { get }

    var destination: BuildDestination { get }

    /// Whether the target is part of the root package that the user opened or if it's part of a package dependency.
    var isPartOfRootPackage: Bool { get }

    var isTestTarget: Bool { get }

    func compileArguments(for fileURL: URL) throws -> [String]
}

private struct WrappedClangTargetBuildDescription: BuildTarget {
    private let description: ClangModuleBuildDescription
    let isPartOfRootPackage: Bool
    let isTestTarget: Bool

    init(description: ClangModuleBuildDescription, isPartOfRootPackage: Bool) {
        self.description = description
        self.isPartOfRootPackage = isPartOfRootPackage
        self.isTestTarget = description.isTestTarget
    }

    public var sources: [SourceItem] {
        guard let compilePaths = try? description.compilePaths() else {
            return []
        }
        return compilePaths.map {
            SourceItem(sourceFile: $0.source.asURL, outputFile: $0.object.asURL)
        }
    }

    public var headers: [URL] {
        return description.clangTarget.headers.map(\.asURL)
    }

    var resources: [URL] {
        return description.resources.map(\.path.asURL)
    }

    var ignored: [URL] {
        return description.ignored.map(\.asURL)
    }

    var others: [URL] {
        var others = Set(description.others)
        for pluginResult in description.buildToolPluginInvocationResults {
            for buildCommand in pluginResult.buildCommands {
                others.formUnion(buildCommand.inputFiles)
            }
        }
        return others.map(\.asURL)
    }

    public var name: String {
        return description.clangTarget.name
    }

    var compiler: BuildTargetCompiler { .clang }


    public var destination: BuildDestination {
        return description.destination == .host ? .host : .target
    }

    public func compileArguments(for fileURL: URL) throws -> [String] {
        let filePath = try resolveSymlinks(try Basics.AbsolutePath(validating: fileURL.path))
        let commandLine = try description.emitCommandLine(for: filePath)
        // First element on the command line is the compiler itself, not an argument.
        return Array(commandLine.dropFirst())
    }
}

private struct WrappedSwiftTargetBuildDescription: BuildTarget {
    private let description: SwiftModuleBuildDescription
    let isPartOfRootPackage: Bool
    let isTestTarget: Bool

    init(description: SwiftModuleBuildDescription, isPartOfRootPackage: Bool) {
        self.description = description
        self.isPartOfRootPackage = isPartOfRootPackage
        self.isTestTarget = description.isTestTarget
    }

    public var name: String {
        return description.target.name
    }

    var compiler: BuildTargetCompiler { .swift }

    public var destination: BuildDestination {
        return description.destination == .host ? .host : .target
    }

    var sources: [SourceItem] {
        return description.sources.map {
            return SourceItem(sourceFile: $0.asURL, outputFile: nil)
        }
    }

    var headers: [URL] { [] }

    var resources: [URL] {
        return description.resources.map(\.path.asURL)
    }

    var ignored: [URL] {
        return description.ignored.map(\.asURL)
    }

    var others: [URL] {
        var others = Set(description.others)
        for pluginResult in description.buildToolPluginInvocationResults {
            for buildCommand in pluginResult.buildCommands {
                others.formUnion(buildCommand.inputFiles)
            }
        }
        return others.map(\.asURL)
    }

    var outputPaths: [URL] {
        get throws {
            struct NotSupportedError: Error, CustomStringConvertible {
                var description: String { "Getting output paths for a Swift target is not supported" }
            }
            throw NotSupportedError()
        }
    }

    func compileArguments(for fileURL: URL) throws -> [String] {
        // Note: we ignore the `fileURL` here as the expectation is that we get a command line for the entire target
        // in case of Swift.
        let commandLine = try description.emitCommandLine(scanInvocation: false, writeOutputFileMap: false)
        // First element on the command line is the compiler itself, not an argument.
        return Array(commandLine.dropFirst())
    }
}

public struct BuildDescription {
    private let buildPlan: Build.BuildPlan

    /// The inputs of the build plan so we don't need to re-compute them  on every call to
    /// `fileAffectsSwiftOrClangBuildSettings`.
    private let inputs: [Build.BuildPlan.Input]

    /// Wrap an already constructed build plan.
    public init(buildPlan: Build.BuildPlan) {
        self.buildPlan = buildPlan
        self.inputs = buildPlan.inputs
    }

    /// Construct a build description, compiling build tool plugins and generating their output when necessary.
    public static func load(
        destinationBuildParameters: BuildParameters,
        toolsBuildParameters: BuildParameters,
        packageGraph: ModulesGraph,
        pluginConfiguration: PluginConfiguration,
        traitConfiguration: TraitConfiguration,
        disableSandbox: Bool,
        scratchDirectory: URL,
        fileSystem: any FileSystem,
        observabilityScope: ObservabilityScope
    ) async throws -> (description: BuildDescription, errors: String) {
        let bufferedOutput = BufferedOutputByteStream()
        let threadSafeOutput = ThreadSafeOutputByteStream(bufferedOutput)

        // This is quite an abuse of `BuildOperation`, building plugins should really be refactored out of it. Though
        // even better would be to have a BSP server that handles both preparing and getting settings.
        // https://github.com/swiftlang/swift-package-manager/issues/8287
        let operation = BuildOperation(
            productsBuildParameters: destinationBuildParameters,
            toolsBuildParameters: toolsBuildParameters,
            cacheBuildManifest: true,
            packageGraphLoader: { packageGraph },
            pluginConfiguration: pluginConfiguration,
            scratchDirectory: try Basics.AbsolutePath(validating: scratchDirectory.path),
            traitConfiguration: traitConfiguration,
            additionalFileRules: FileRuleDescription.swiftpmFileTypes,
            pkgConfigDirectories: [],
            outputStream: threadSafeOutput,
            logLevel: .error,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope
        )

        let plan = try await operation.generatePlan()
        return (BuildDescription(buildPlan: plan), bufferedOutput.bytes.description)
    }

    func getBuildTarget(
        for module: ResolvedModule,
        destination: BuildParameters.Destination
    ) -> BuildTarget? {
        if let description = self.buildPlan.description(for: module, context: destination) {
            let modulesGraph = self.buildPlan.graph
            switch description {
            case .clang(let description):
                return WrappedClangTargetBuildDescription(
                    description: description,
                    isPartOfRootPackage: modulesGraph.rootPackages.map(\.id).contains(description.package.id)
                )
            case .swift(let description):
                return WrappedSwiftTargetBuildDescription(
                    description: description,
                    isPartOfRootPackage: modulesGraph.rootPackages.map(\.id).contains(description.package.id)
                )
            }
        } else {
            if module.type == .plugin, let package = self.buildPlan.graph.package(for: module) {
                let modulesGraph = self.buildPlan.graph
                return PluginTargetBuildDescription(
                    target: module,
                    toolsVersion: package.manifest.toolsVersion,
                    toolchain: buildPlan.toolsBuildParameters.toolchain,
                    isPartOfRootPackage: modulesGraph.rootPackages.map(\.id).contains(package.id)
                )
            }
            return nil
        }
    }

    public func traverseModules(
        callback: (any BuildTarget, _ parent: (any BuildTarget)?) -> Void
    ) {
        self.buildPlan.traverseModules { module, parent in
            let parentDescription: (any BuildTarget)? = if let parent {
                getBuildTarget(for: parent.0, destination: parent.1)
            } else {
                nil
            }

            if let description = getBuildTarget(for: module.0, destination: module.1) {
                callback(description, parentDescription)
            }
        }
    }

    /// Returns `true` if the file at the given path might influence build settings for a `swiftc` or `clang` invocation
    /// generated by SwiftPM.
    public func fileAffectsSwiftOrClangBuildSettings(_ url: URL) -> Bool {
        guard let filePath = try? Basics.AbsolutePath(validating: url.path) else {
            return false
        }

        for input in self.inputs {
            switch input {
            case .directoryStructure(let path):
                if path.isAncestor(of: filePath) {
                    return true
                }
            case .file(let path):
                if filePath == path {
                    return true
                }
            }
        }
        return false
    }
}
