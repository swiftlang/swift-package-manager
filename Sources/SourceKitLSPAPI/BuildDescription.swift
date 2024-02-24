//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

private import struct Basics.AbsolutePath
private import func Basics.resolveSymlinks
// FIXME: should not import this module
import Build
// FIXME: should be internal imports
import PackageGraph
private import SPMBuildCore

public protocol BuildTarget {
    var sources: [URL] { get }

    func compileArguments(for fileURL: URL) throws -> [String]
 }

extension ClangTargetBuildDescription: BuildTarget {
    public var sources: [URL] {
        return (try? compilePaths().map { URL(fileURLWithPath: $0.source.pathString) }) ?? []
    }

    public func compileArguments(for fileURL: URL) throws -> [String] {
        let filePath = try resolveSymlinks(try AbsolutePath(validating: fileURL.path))
        return try self.emitCommandLine(for: filePath)
    }
}

private struct WrappedSwiftTargetBuildDescription: BuildTarget {
    private let description: SwiftTargetBuildDescription

    init(description: SwiftTargetBuildDescription) {
        self.description = description
    }

    var sources: [URL] {
        return description.sources.map { URL(fileURLWithPath: $0.pathString) }
    }

    func compileArguments(for fileURL: URL) throws -> [String] {
        // Note: we ignore the `fileURL` here as the expectation is that we get a commandline for the entire target in case of Swift.
        return try description.emitCommandLine(scanInvocation: false)
    }
}

public struct BuildDescription {
    private let buildPlan: Build.BuildPlan

    // FIXME: should not use `BuildPlan` in the public interface
    public init(buildPlan: Build.BuildPlan) {
        self.buildPlan = buildPlan
    }

    // FIXME: should not use `ResolvedTarget` in the public interface
    public func getBuildTarget(for target: ResolvedTarget) -> BuildTarget? {
        if let description = buildPlan.targetMap[target.id] {
            switch description {
            case .clang(let description):
                return description
            case .swift(let description):
                return WrappedSwiftTargetBuildDescription(description: description)
            }
        } else {
            if target.type == .plugin, let package = self.buildPlan.graph.package(for: target) {
                return PluginTargetBuildDescription(target: target, toolsVersion: package.manifest.toolsVersion)
            }
            return nil
        }
    }
}
