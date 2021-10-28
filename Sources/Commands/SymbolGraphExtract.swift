/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2022 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import ArgumentParser
import Basics
import Build
import Foundation
import PackageGraph
import PackageModel
import SPMBuildCore
import SymbolKit
import SnippetModel
import TSCBasic
import TSCUtility

/// A wrapper for swift-symbolgraph-extract tool.
public struct SymbolGraphExtract {
    let tool: AbsolutePath
    
    var skipSynthesizedMembers = false
    var minimumAccessLevel = AccessLevel.public
    var skipInheritedDocs = false
    var includeSPISymbols = false
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

    public func emitSymbolGraphs(forSnippetGroups snippetGroups: [SnippetGroup], to emitPath: AbsolutePath, package: ResolvedPackage) throws {
        var groups = [SymbolGraph.Symbol]()
        var snippets = [SymbolGraph.Symbol]()
        var relationships = [SymbolGraph.Relationship]()

        for group in snippetGroups {
            let groupSymbol = SymbolGraph.Symbol(group, packageName: package.manifest.displayName)
            let snippetSymbols = group.snippets.map {
                SymbolGraph.Symbol($0, packageName: package.manifest.displayName, groupName: group.name)
            }

            groups.append(groupSymbol)
            snippets.append(contentsOf: snippetSymbols)

            let snippetGroupRelationships = snippetSymbols.map { snippetSymbol in
                SymbolGraph.Relationship(source: snippetSymbol.identifier.precise, target: groupSymbol.identifier.precise, kind: .memberOf, targetFallback: nil)
            }
            relationships.append(contentsOf: snippetGroupRelationships)
        }

        let metadata = SymbolGraph.Metadata(formatVersion: .init(major: 0, minor: 1, patch: 0), generator: "SwiftPM")
        let module = SymbolGraph.Module(name: package.manifest.displayName, platform: .init(architecture: nil, vendor: nil, operatingSystem: nil, environment: nil))
        let symbolGraph = SymbolGraph(metadata: metadata, module: module, symbols: groups + snippets, relationships: relationships)
        let encoder = JSONEncoder()
        let data = try encoder.encode(symbolGraph)
        try data.write(to: emitPath.appending(component: "\(package.manifest.displayName)-snippets.symbols.json").asURL)
    }
    
    /// Creates a symbol graph for `target` in `outputDirectory` using the build information from `buildPlan`. The `outputDirection` determines how the output from the tool subprocess is handled, and `verbosity` specifies how much console output to ask the tool to emit.
    public func extractSymbolGraph(
        target: ResolvedTarget,
        buildPlan: BuildPlan,
        outputRedirection: TSCBasic.Process.OutputRedirection = .none,
        logLevel: Basics.Diagnostic.Severity,
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
        if logLevel <= .info {
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
        switch outputFormat {
        case .json(let pretty):
            if pretty {
                commandLine += ["-pretty-print"]
            }
        }
        commandLine += ["-output-dir", outputDirectory.pathString]

        // Run the extraction.
        let process = Process(
            arguments: commandLine,
            outputRedirection: outputRedirection,
            verbose: logLevel <= .info)
        try process.launch()
        try process.waitUntilExit()

        let snippetGroups = try [SnippetGroup](fromPackage: buildPlan.graph.rootPackages[0])
        if !snippetGroups.isEmpty {
            try emitSymbolGraphs(forSnippetGroups: snippetGroups, to: outputDirectory, package: buildPlan.graph.rootPackages[0])
        }
    }
}

extension SymbolGraph.Symbol {
    fileprivate init(_ snippetGroup: SnippetGroup, packageName: String) {
        let identifier = SymbolGraph.Symbol.Identifier(precise: "$snippet__\(packageName).\(snippetGroup.name)", interfaceLanguage: "swift")
        let names = SymbolGraph.Symbol.Names.init(title: snippetGroup.name, navigator: nil, subHeading: nil, prose: nil)
        let pathComponents = [snippetGroup.name]
        let docComment = SymbolGraph.LineList(snippetGroup.explanation
                                    .split(separator: "\n", maxSplits: Int.max, omittingEmptySubsequences: false)
                                    .map { line in
            SymbolGraph.LineList.Line(text: String(line), range: nil)
        })
        let accessLevel = SymbolGraph.Symbol.AccessControl(rawValue: "public")
        let kind = SymbolGraph.Symbol.Kind(rawIdentifier: "swift.snippetGroup", displayName: "Snippet")
        self.init(identifier: identifier, names: names, pathComponents: pathComponents, docComment: docComment, accessLevel: accessLevel, kind: kind, mixins: [:])
    }

    fileprivate init(_ snippet: SnippetModel.Snippet, packageName: String, groupName: String) {
        let identifier = SymbolGraph.Symbol.Identifier(precise: "$snippet__\(packageName).\(groupName).\(snippet.name)", interfaceLanguage: "swift")
        let names = SymbolGraph.Symbol.Names.init(title: snippet.name, navigator: nil, subHeading: nil, prose: nil)
        let pathComponents = [packageName, groupName, snippet.name]
        let docComment = SymbolGraph.LineList(snippet.explanation
                                    .split(separator: "\n", maxSplits: Int.max, omittingEmptySubsequences: false)
                                    .map { line in
            SymbolGraph.LineList.Line(text: String(line), range: nil)
        })
        let accessLevel = SymbolGraph.Symbol.AccessControl(rawValue: "public")

        let kind = SymbolGraph.Symbol.Kind(rawIdentifier: "swift.snippet", displayName: "Snippet")
        self.init(identifier: identifier, names: names, pathComponents: pathComponents, docComment: docComment, accessLevel: accessLevel, kind: kind, mixins: [
            SymbolGraph.Symbol.Snippet.mixinKey: SymbolGraph.Symbol.Snippet(chunks: [SymbolGraph.Symbol.Snippet.Chunk(name: nil, language: "swift", code: snippet.presentationCode)])
        ])
    }
}
