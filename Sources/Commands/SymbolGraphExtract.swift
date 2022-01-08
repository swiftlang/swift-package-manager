/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2022 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import ArgumentParser
import Build
import PackageGraph
import PackageModel
import SPMBuildCore
import TSCBasic
import TSCUtility

/// A wrapper for swift-symbolgraph-extract tool.
public struct SymbolGraphExtract {
    let tool: AbsolutePath
    var skipSynthesizedMembers: Bool = false
    var minimumAccessLevel: AccessLevel = .public
    var skipInheritedDocs: Bool = false
    var includeSPISymbols: Bool = false
    var prettyPrintOutputJSON: Bool = false

    /// Access control levels.
    public enum AccessLevel: String, RawRepresentable, CustomStringConvertible, CaseIterable, ExpressibleByArgument {
        // The cases reflect those found in `include/swift/AST/AttrKind.h` of the swift compiler (at commit 03f55d7bb4204ca54841218eb7cc175ae798e3bd)
        case `private`, `fileprivate`, `internal`, `public`, `open`

        public var description: String { rawValue }
    }

    /// Creates a symbol graph for `target` in `outputDirectory` using the build information from `buildPlan`. The `outputDirection` determines how the output from the tool subprocess is handled, and `verbosity` specifies how much console output to ask the tool to emit.
    public func extractSymbolGraph(
        target: ResolvedTarget,
        buildPlan: BuildPlan,
        outputRedirection: Process.OutputRedirection = .none,
        verbose: Bool,
        outputDirectory: AbsolutePath
    ) throws {
        let buildParameters = buildPlan.buildParameters
        try localFileSystem.createDirectory(outputDirectory, recursive: true)

        // Construct arguments for extracting symbols for a single target.
        var commandLine = [self.tool.pathString]
        commandLine += ["-module-name", target.c99name]
        commandLine += try buildParameters.targetTripleArgs(for: target)
        commandLine += buildPlan.createAPIToolCommonArgs(includeLibrarySearchPaths: true)
        commandLine += ["-module-cache-path", buildParameters.moduleCache.pathString]
        if verbose {
            commandLine += ["-v"]
        }
        commandLine += ["-minimum-access-level", minimumAccessLevel.rawValue]
        if skipSynthesizedMembers {
            commandLine += ["-skip-synthesized-members"]
        }
        if skipInheritedDocs {
            commandLine += ["-skip-inherited-docs"]
        }
        if includeSPISymbols {
            commandLine += ["-include-spi-symbols"]
        }
        if prettyPrintOutputJSON {
            commandLine += ["-pretty-print"]
        }
        commandLine += ["-output-dir", outputDirectory.pathString]

        // Run the extraction.
        let process = Process(
            arguments: commandLine,
            outputRedirection: outputRedirection,
            verbose: verbose)
        try process.launch()
        try process.waitUntilExit()
    }
}
