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
import Basics
import CoreCommands
import Foundation
import PackageModel
import PackageGraph
import SPMBuildCore
import TSCBasic
import Workspace
import XCBuildSupport

struct DumpSymbolGraph: AsyncSwiftCommand {
    static let configuration = CommandConfiguration(
        abstract: "Dump symbol graphs.")
    static let defaultMinimumAccessLevel = SymbolGraphExtract.AccessLevel.public

    @OptionGroup(visibility: .hidden)
    var globalOptions: GlobalOptions

    @Flag(help: "Pretty-print the output JSON.")
    var prettyPrint = false

    @Flag(help: "Skip members inherited through classes or default implementations.")
    var skipSynthesizedMembers = false

    @Option(help: "Include symbols with this access level or more. Possible values: \(SymbolGraphExtract.AccessLevel.allValueStrings.joined(separator: " | ")).")
    var minimumAccessLevel = defaultMinimumAccessLevel

    @Flag(help: "Skip emitting doc comments for members inherited through classes or default implementations.")
    var skipInheritedDocs = false

    @Flag(help: "Add symbols with SPI information to the symbol graph.")
    var includeSPISymbols = false
    
    @Flag(help: "Emit extension block symbols for extensions to external types or directly associate members and conformances with the extended nominal.")
    var extensionBlockSymbolBehavior: ExtensionBlockSymbolBehavior = .omitExtensionBlockSymbols

    func run(_ swiftCommandState: SwiftCommandState) async throws {
        // Build the current package.
        //
        // We turn build manifest caching off because we need the build plan.
        let buildSystem = try await swiftCommandState.createBuildSystem(
            // We are enabling all traits for dumping the symbol graph.
            enableAllTraits: true,
            cacheBuildManifest: false
        )
        let buildResult = try await buildSystem.build(subset: .allExcludingTests, buildOutputs: [.symbolGraph(
            BuildOutput.SymbolGraphOptions(
                prettyPrint: prettyPrint,
                minimumAccessLevel: .accessLevel(minimumAccessLevel),
                includeInheritedDocs: !skipInheritedDocs,
                includeSynthesized: !skipSynthesizedMembers,
                includeSPI: includeSPISymbols,
                emitExtensionBlocks: extensionBlockSymbolBehavior != .omitExtensionBlockSymbols,
            )
        ), .buildPlan])

        let symbolGraphDirectory = try swiftCommandState.productsBuildParameters.dataPath.appending("symbolgraph")

        let fs = swiftCommandState.fileSystem

        try? fs.removeFileTree(symbolGraphDirectory)
        try fs.createDirectory(symbolGraphDirectory, recursive: true)

        if let symbolGraph = buildResult.symbolGraph {
            // The build system produced symbol graphs for us, one for each target.
            let buildPath = try swiftCommandState.productsBuildParameters.buildPath

            // Copy the symbol graphs from the target-specific locations to the single output directory
            for rootPackage in try await buildSystem.getPackageGraph().rootPackages {
                for module in rootPackage.modules {
                    let sgDir = symbolGraph.outputLocationForTarget(module.name, try swiftCommandState.productsBuildParameters)

                    if case let sgDir = buildPath.appending(components: sgDir), fs.exists(sgDir) {
                        for sgFile in try fs.getDirectoryContents(sgDir) {
                            try fs.copy(from: sgDir.appending(components: sgFile), to: symbolGraphDirectory.appending(sgFile))
                        }
                    }
                }
            }
        } else if let buildPlan = buildResult.buildPlan {
            // Otherwise, with a build plan we can run the symbol graph extractor tool on the built targets.
            let symbolGraphExtractor = try SymbolGraphExtract(
                fileSystem: swiftCommandState.fileSystem,
                tool: swiftCommandState.getTargetToolchain().getSymbolGraphExtract(),
                observabilityScope: swiftCommandState.observabilityScope,
                skipSynthesizedMembers: skipSynthesizedMembers,
                minimumAccessLevel: minimumAccessLevel,
                skipInheritedDocs: skipInheritedDocs,
                includeSPISymbols: includeSPISymbols,
                emitExtensionBlockSymbols: extensionBlockSymbolBehavior == .emitExtensionBlockSymbols,
                outputFormat: .json(pretty: prettyPrint)
            )

            // Run the tool once for every library and executable target in the root package.
            let modulesGraph = try await buildSystem.getPackageGraph()
            for description in buildPlan.buildModules {
                guard description.module.type == .library,
                    modulesGraph.rootPackages[description.package.id] != nil
                else {
                    continue
                }

                print("-- Emitting symbol graph for", description.module.name)
                let result = try symbolGraphExtractor.extractSymbolGraph(
                    for: description,
                    outputRedirection: .collect(redirectStderr: true),
                    outputDirectory: symbolGraphDirectory,
                    verboseOutput: swiftCommandState.logLevel <= .info
                )

                if result.exitStatus != .terminated(code: 0) {
                    let commandline = "\nUsing commandline: \(result.arguments)"
                    switch result.output {
                    case .success(let value):
                        swiftCommandState.observabilityScope.emit(error: "Failed to emit symbol graph for '\(description.module.c99name)': \(String(decoding: value, as: UTF8.self))\(commandline)")
                    case .failure(let error):
                        swiftCommandState.observabilityScope.emit(error: "Internal error while emitting symbol graph for '\(description.module.c99name)': \(error)\(commandline)")
                    }
                }
            }
        } else {
            throw InternalError("Build system \(buildSystem) cannot produce a symbol graph.")
        }

        print("Files written to", symbolGraphDirectory.pathString)
    }
}

enum ExtensionBlockSymbolBehavior: String, EnumerableFlag {
    case emitExtensionBlockSymbols
    case omitExtensionBlockSymbols
}

struct DumpPackage: AsyncSwiftCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print parsed Package.swift as JSON.")

    @OptionGroup(visibility: .hidden)
    var globalOptions: GlobalOptions

    func run(_ swiftCommandState: SwiftCommandState) async throws {
        let workspace = try swiftCommandState.getActiveWorkspace()
        let root = try swiftCommandState.getWorkspaceRoot()

        let rootManifests = try await workspace.loadRootManifests(
            packages: root.packages,
            observabilityScope: swiftCommandState.observabilityScope
        )
        guard let rootManifest = rootManifests.values.first else {
            throw StringError("invalid manifests at \(root.packages)")
        }

        let encoder = JSONEncoder.makeWithDefaults()
        encoder.userInfo[Manifest.dumpPackageKey] = true

        let jsonData = try encoder.encode(rootManifest)
        let jsonString = String(decoding: jsonData, as: UTF8.self)
        print(jsonString)
    }
}

struct DumpPIF: AsyncSwiftCommand {
    // hides this command from CLI `--help` output
    static let configuration = CommandConfiguration(shouldDisplay: false)

    @OptionGroup(visibility: .private)
    var globalOptions: GlobalOptions

    @Flag(help: "Preserve the internal structure of PIF")
    var preserveStructure: Bool = false

    func run(_ swiftCommandState: SwiftCommandState) async throws {
        let graph = try await swiftCommandState.loadPackageGraph()
        let pif = try PIFBuilder.generatePIF(
            buildParameters: swiftCommandState.productsBuildParameters,
            packageGraph: graph,
            fileSystem: swiftCommandState.fileSystem,
            observabilityScope: swiftCommandState.observabilityScope,
            preservePIFModelStructure: preserveStructure)
        print(pif)
    }

    var toolWorkspaceConfiguration: ToolWorkspaceConfiguration {
        return .init(wantsMultipleTestProducts: true)
    }
}

fileprivate extension BuildOutput.SymbolGraphAccessLevel {
    fileprivate static func accessLevel(_ accessLevel: SymbolGraphExtract.AccessLevel) -> BuildOutput.SymbolGraphAccessLevel {
        return BuildOutput.SymbolGraphAccessLevel.init(rawValue: accessLevel.rawValue)!
    }
}
