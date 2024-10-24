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

import struct Foundation.URL

private import struct Basics.AbsolutePath
private import func Basics.resolveSymlinks

internal import SPMBuildCore

// FIXME: should import these module with `private` or `internal` access control
import class Build.BuildPlan
import class Build.ClangModuleBuildDescription
import class Build.SwiftModuleBuildDescription
import struct PackageGraph.ResolvedModule
import struct PackageGraph.ModulesGraph
internal import class PackageModel.UserToolchain

public enum BuildDestination {
    case host
    case target
}

public protocol BuildTarget {
    /// Source files in the target
    var sources: [URL] { get }

    /// Header files in the target
    var headers: [URL] { get }

    /// The name of the target. It should be possible to build a target by passing this name to `swift build --target`
    var name: String { get }

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

    public var sources: [URL] {
        guard let compilePaths = try? description.compilePaths() else {
            return []
        }
        return compilePaths.map(\.source.asURL)
    }

    public var headers: [URL] {
        return description.clangTarget.headers.map(\.asURL)
    }

    public var name: String {
        return description.clangTarget.name
    }

    public var destination: BuildDestination {
        return description.destination == .host ? .host : .target
    }

    public func compileArguments(for fileURL: URL) throws -> [String] {
        let filePath = try resolveSymlinks(try AbsolutePath(validating: fileURL.path))
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

    public var destination: BuildDestination {
        return description.destination == .host ? .host : .target
    }

    var sources: [URL] {
        return description.sources.map { URL(fileURLWithPath: $0.pathString) }
    }

    var headers: [URL] { [] }

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
    private let inputs: [BuildPlan.Input]

    // FIXME: should not use `BuildPlan` in the public interface
    public init(buildPlan: Build.BuildPlan) {
        self.buildPlan = buildPlan
        self.inputs = buildPlan.inputs
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
        guard let filePath = try? AbsolutePath(validating: url.path) else {
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
