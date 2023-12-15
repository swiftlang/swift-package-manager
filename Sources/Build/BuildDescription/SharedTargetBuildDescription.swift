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

import Basics
import PackageGraph
import PackageLoading
import PackageModel
import SPMBuildCore

import struct Basics.AbsolutePath

/// Shared functionality between `ClangTargetBuildDescription` and `SwiftTargetBuildDescription` with the eventual hope of having a single type.
struct SharedTargetBuildDescription {
    static func computePluginGeneratedFiles(
        target: ResolvedTarget,
        toolsVersion: ToolsVersion,
        additionalFileRules: [FileRuleDescription],
        buildParameters: BuildParameters,
        buildToolPluginInvocationResults: [BuildToolPluginInvocationResult],
        prebuildCommandResults: [PrebuildCommandResult],
        observabilityScope: ObservabilityScope
    ) -> (pluginDerivedSources: Sources, pluginDerivedResources: [Resource]) {
        var pluginDerivedSources = Sources(paths: [], root: buildParameters.dataPath)

        // Add any derived files that were declared for any commands from plugin invocations.
        var pluginDerivedFiles = [AbsolutePath]()
        for command in buildToolPluginInvocationResults.reduce([], { $0 + $1.buildCommands }) {
            for absPath in command.outputFiles {
                pluginDerivedFiles.append(absPath)
            }
        }

        // Add any derived files that were discovered from output directories of prebuild commands.
        for result in prebuildCommandResults {
            for path in result.derivedFiles {
                pluginDerivedFiles.append(path)
            }
        }

        // Let `TargetSourcesBuilder` compute the treatment of plugin generated files.
        let (derivedSources, derivedResources) = TargetSourcesBuilder.computeContents(
            for: pluginDerivedFiles,
            toolsVersion: toolsVersion,
            additionalFileRules: additionalFileRules,
            defaultLocalization: target.defaultLocalization,
            targetName: target.name,
            targetPath: target.underlying.path,
            observabilityScope: observabilityScope
        )
        let pluginDerivedResources = derivedResources
        derivedSources.forEach { absPath in
            let relPath = absPath.relative(to: pluginDerivedSources.root)
            pluginDerivedSources.relativePaths.append(relPath)
        }

        return (pluginDerivedSources, pluginDerivedResources)
    }
}
