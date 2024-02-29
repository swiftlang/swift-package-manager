//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2015-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import PackageGraph
import PackageModel

import struct Basics.InternalError
import protocol Basics.FileSystem

/// Description for a plugin target. This is treated a bit differently from the
/// regular kinds of targets, and is not included in the LLBuild description.
/// But because the package graph and build plan are not loaded for incremental
/// builds, this information is included in the BuildDescription, and the plugin
/// targets are compiled directly.
public final class PluginDescription: Codable {
    /// The identity of the package in which the plugin is defined.
    public let package: PackageIdentity

    /// The name of the plugin target in that package (this is also the name of
    /// the plugin).
    public let targetName: String

    /// The names of any plugin products in that package that vend the plugin
    /// to other packages.
    public let productNames: [String]

    /// The tools version of the package that declared the target. This affects
    /// the API that is available in the PackagePlugin module.
    public let toolsVersion: ToolsVersion

    /// Swift source files that comprise the plugin.
    public let sources: Sources

    /// Initialize a new plugin target description. The target is expected to be
    /// a `PluginTarget`.
    init(
        target: ResolvedTarget,
        products: [ResolvedProduct],
        package: ResolvedPackage,
        toolsVersion: ToolsVersion,
        testDiscoveryTarget: Bool = false,
        fileSystem: FileSystem
    ) throws {
        guard target.underlying is PluginTarget else {
            throw InternalError("underlying target type mismatch \(target)")
        }

        self.package = package.identity
        self.targetName = target.name
        self.productNames = products.map(\.name)
        self.toolsVersion = toolsVersion
        self.sources = target.sources
    }
}
