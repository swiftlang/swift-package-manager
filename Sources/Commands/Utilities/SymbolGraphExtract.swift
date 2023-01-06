//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import Build
import Basics
import PackageGraph
import PackageModel
import SPMBuildCore
import TSCBasic
@_implementationOnly import DriverSupport

/// A wrapper for swift-symbolgraph-extract tool.
public struct SymbolGraphExtract {
    let fileSystem: FileSystem
    
    /// The absolute path to the Swift symbol graph extract tool
    ///
    /// This is the tool that should be used when extracting symbol graphs from Swift targets.
    let swiftSymbolGraphExtract: AbsolutePath
    
    /// The absolute path to the clang compiler.
    ///
    /// This is the tool that should be used when extracting symbol graphs from Clang targets.
    let clangCompiler: AbsolutePath
    
    let observabilityScope: ObservabilityScope
    
    var skipSynthesizedMembers = false
    var minimumAccessLevel = AccessLevel.public
    var skipInheritedDocs = false
    var includeSPISymbols = false
    var emitExtensionBlockSymbols = false
    var outputFormat = OutputFormat.json(pretty: false)

    /// Access control levels.
    public enum AccessLevel: String, RawRepresentable, CaseIterable, ExpressibleByArgument {
        // The cases reflect those found in `include/swift/AST/AttrKind.h` of the swift compiler (at commit 03f55d7bb4204ca54841218eb7cc175ae798e3bd)
        case `private`, `fileprivate`, `internal`, `public`, `open`
    }

    /// Output format of the generated symbol graph.
    public enum OutputFormat {
        /// JSON format, optionally "pretty-printed" be more human-readable.
        case json(pretty: Bool)
    }
    
    /// Creates a symbol graph for `target` in `outputDirectory` using the build information from `buildPlan`. The `outputDirection` determines how the output from the tool subprocess is handled, and `verbosity` specifies how much console output to ask the tool to emit.
    public func extractSymbolGraph(
        target: ResolvedTarget,
        buildPlan: SPMBuildCore.BuildPlan,
        outputRedirection: TSCBasic.Process.OutputRedirection = .none,
        outputDirectory: AbsolutePath,
        verboseOutput: Bool
    ) throws {
        if target.underlyingTarget is SwiftTarget {
            try extractSymbolGraphFromSwiftTarget(
                target: target,
                buildPlan: buildPlan,
                outputRedirection: outputRedirection,
                outputDirectory: outputDirectory.appending(component: "swift"),
                verboseOutput: verboseOutput
            )
        } else if let clangTarget = target.underlyingTarget as? ClangTarget,
                  case let .clang(buildDescription) = (buildPlan as? Build.BuildPlan)?.targetMap[target]
        {
            try extractSymbolGraphFromClangTarget(
                target: clangTarget,
                buildDescription: buildDescription,
                outputRedirection: outputRedirection,
                outputDirectory: outputDirectory.appending(component: "clang"),
                verboseOutput: verboseOutput
            )
        } else {
            // Just skip unsupported targets for now. `swift package dump-symbol-graph` attempts
            // to go through all targets so throwing an error for unsupported targets just creates
            // noise.
        }
    }
    
    func extractSymbolGraphFromClangTarget(
        target: ClangTarget,
        buildDescription: ClangTargetBuildDescription,
        outputRedirection: Process.OutputRedirection,
        outputDirectory: AbsolutePath,
        verboseOutput: Bool
    ) throws {
        var relevantHeaders: Set<AbsolutePath>
        switch minimumAccessLevel {
        case .private, .fileprivate, .internal:
            relevantHeaders = Set(target.headers)
            
            guard !relevantHeaders.isEmpty else {
                observabilityScope.emit(
                    warning: "skipped \(target.name) target because no headers were found"
                )
                return
            }
        case .public, .open:
            // Collect the set of public headers by filtering all of the target's headers to those
            // inside the target's include directory.
            relevantHeaders = Set(target.headers.filter(target.includeDir.isAncestor))
            
            guard !relevantHeaders.isEmpty else {
                observabilityScope.emit(
                    warning: "skipped \(target.name) target because no public headers were found"
                )
                return
            }
        }
        
        let umbrellaHeader: AbsolutePath?
        switch target.moduleMapType {
        case .umbrellaHeader(let umbrellaHeaderFile):
            // The target is configured with an umbrella header – store its path separately
            // and remove it from the general list of public headers.
            umbrellaHeader = umbrellaHeaderFile
            relevantHeaders.remove(umbrellaHeaderFile)
        case .umbrellaDirectory(_):
            // TODO: Support symbol graph extraction for umbrella directory module map type
            fallthrough
        case .custom(_):
            // TODO: Support symbol graph extraction for custom module map file type
            fallthrough
        case .none:
            umbrellaHeader = nil
        }
        
        try fileSystem.createDirectory(outputDirectory, recursive: true)
        
        // Construct the command line arguments for extracting the symbol graph
        var commandLine = [
            clangCompiler.pathString, "-extract-api",
            "--product-name=\(target.c99name)",
            "-o", outputDirectory.appending(component: "\(target.name).symbols.json").pathString
        ]
        
        if verboseOutput {
            commandLine += ["-v"]
        }
        
        switch outputFormat {
        case .json(let pretty):
            if pretty {
                // TODO: Specify pretty print behavior to `-extract-api` when it's supported.
                // commandLine += ["-pretty-print"]
            }
        }
        
        // TODO: Support symbol graph extraction for C++ targets
        guard !target.sources.containsCXXFiles else {
            observabilityScope.emit(warning: "skipped \(target.name) target because symbol graph extraction is not supported for C++ targets")
            return
        }
        
        commandLine += try buildDescription.basicArguments(
            isCXX: target.sources.containsCXXFiles,
            isC: target.sources.containsCFiles
        )
        
        // Pass the paths of all public headers to the extract-api command
        commandLine += ["-x", "objective-c-header"]
        
        // If an umbrella header has been provided, pass it first
        if let umbrellaHeader = umbrellaHeader {
            commandLine += [umbrellaHeader.pathString]
        }
        // Then provide the remaining relevant headers in a deterministic order
        commandLine += relevantHeaders.lazy.map(\.pathString).sorted()
        
        // Run the extraction
        let process = TSCBasic.Process(
            arguments: commandLine,
            outputRedirection: outputRedirection
        )
        try process.launch()
        try process.waitUntilExit()
    }
    
    func extractSymbolGraphFromSwiftTarget(
        target: ResolvedTarget,
        buildPlan: SPMBuildCore.BuildPlan,
        outputRedirection: Process.OutputRedirection,
        outputDirectory: AbsolutePath,
        verboseOutput: Bool
    ) throws {
        let buildParameters = buildPlan.buildParameters
        try self.fileSystem.createDirectory(outputDirectory, recursive: true)

        // Construct arguments for extracting symbols for a single target.
        var commandLine = [self.swiftSymbolGraphExtract.pathString]
        commandLine += ["-module-name", target.c99name]
        commandLine += try buildParameters.targetTripleArgs(for: target)
        commandLine += try buildPlan.createAPIToolCommonArgs(includeLibrarySearchPaths: true)
        commandLine += ["-module-cache-path", try buildParameters.moduleCache.pathString]
        if verboseOutput {
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
        
        let extensionBlockSymbolsFlag = emitExtensionBlockSymbols ? "-emit-extension-block-symbols" : "-omit-extension-block-symbols"
        if DriverSupport.checkSupportedFrontendFlags(flags: [extensionBlockSymbolsFlag.trimmingCharacters(in: ["-"])], fileSystem: fileSystem) {
            commandLine += [extensionBlockSymbolsFlag]
        } else {
            observabilityScope.emit(warning: "dropped \(extensionBlockSymbolsFlag) flag because it is not supported by this compiler version")
        }
        
        switch outputFormat {
        case .json(let pretty):
            if pretty {
                commandLine += ["-pretty-print"]
            }
        }
        commandLine += ["-output-dir", outputDirectory.pathString]

        // Run the extraction.
        let process = TSCBasic.Process(
            arguments: commandLine,
            outputRedirection: outputRedirection
        )
        try process.launch()
        try process.waitUntilExit()
    }
}
