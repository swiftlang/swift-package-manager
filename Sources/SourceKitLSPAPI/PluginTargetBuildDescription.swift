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

// FIXME: should be an internal import
import class PackageGraph.ResolvedTarget

/*private*/ import class PackageLoading.ManifestLoader
/*private*/ import struct PackageModel.ToolsVersion
/*private*/ import class PackageModel.UserToolchain

struct PluginTargetBuildDescription: BuildTarget {
    private let target: ResolvedTarget
    private let toolsVersion: ToolsVersion

    init(target: ResolvedTarget, toolsVersion: ToolsVersion) {
        assert(target.type == .plugin)
        self.target = target
        self.toolsVersion = toolsVersion
    }

    var sources: [URL] {
        return target.sources.paths.map { URL(fileURLWithPath: $0.pathString) }
    }

    func compileArguments(for fileURL: URL) throws -> [String] {
        // FIXME: This is very odd and we should clean this up by merging `ManifestLoader` and `DefaultPluginScriptRunner` again.
        let loader = ManifestLoader(toolchain: try UserToolchain(swiftSDK: .hostSwiftSDK()))
        var args = loader.interpreterFlags(for: self.toolsVersion)
        // Note: we ignore the `fileURL` here as the expectation is that we get a commandline for the entire target in case of Swift. Plugins are always assumed to only consist of Swift files.
        args += sources.map { $0.path }
        return args
    }
}
