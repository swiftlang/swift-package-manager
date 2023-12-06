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
import XCBuildSupport

struct DumpSymbolGraph: SwiftCommand {
    static let configuration = CommandConfiguration(
        abstract: "Dump Symbol Graph")
    static let defaultMinimumAccessLevel = SymbolGraphExtract.AccessLevel.public

    @OptionGroup(visibility: .hidden)
    var globalOptions: GlobalOptions

    @Flag(help: "Pretty-print the output JSON.")
    var prettyPrint = false

    @Flag(help: "Skip members inherited through classes or default implementations.")
    var skipSynthesizedMembers = false

    @Option(help: "Include symbols with this access level or more. Possible values: \(SymbolGraphExtract.AccessLevel.allValueStrings.joined(separator: " | "))")
    var minimumAccessLevel = defaultMinimumAccessLevel

    @Flag(help: "Skip emitting doc comments for members inherited through classes or default implementations.")
    var skipInheritedDocs = false

    @Flag(help: "Add symbols with SPI information to the symbol graph.")
    var includeSPISymbols = false
    
    @Flag(help: "Emit extension block symbols for extensions to external types or directly associate members and conformances with the extended nominal.")
    var extensionBlockSymbolBehavior: ExtensionBlockSymbolBehavior = .omitExtensionBlockSymbols

    func run(_ swiftTool: SwiftTool) throws {
        // Build the current package.
        //
        // We turn build manifest caching off because we need the build plan.
        let buildSystem = try swiftTool.createBuildSystem(explicitBuildSystem: .native, cacheBuildManifest: false)
        try buildSystem.build()

        // Configure the symbol graph extractor.
        let symbolGraphExtractor = try SymbolGraphExtract(
            fileSystem: swiftTool.fileSystem,
            tool: swiftTool.getTargetToolchain().getSymbolGraphExtract(),
            observabilityScope: swiftTool.observabilityScope,
            skipSynthesizedMembers: skipSynthesizedMembers,
            minimumAccessLevel: minimumAccessLevel,
            skipInheritedDocs: skipInheritedDocs,
            includeSPISymbols: includeSPISymbols,
            emitExtensionBlockSymbols: extensionBlockSymbolBehavior == .emitExtensionBlockSymbols,
            outputFormat: .json(pretty: prettyPrint)
        )

        // Run the tool once for every library and executable target in the root package.
        let buildPlan = try buildSystem.buildPlan
        let symbolGraphDirectory = buildPlan.buildParameters.dataPath.appending("symbolgraph")
        let targets = try buildSystem.getPackageGraph().rootPackages.flatMap{ $0.targets }.filter{ $0.type == .library }
        for target in targets {
            print("-- Emitting symbol graph for", target.name)
            let result = try symbolGraphExtractor.extractSymbolGraph(
                target: target,
                buildPlan: buildPlan,
                outputRedirection: .collect(redirectStderr: true),
                outputDirectory: symbolGraphDirectory,
                verboseOutput: swiftTool.logLevel <= .info
            )

            if result.exitStatus != .terminated(code: 0) {
                switch result.output {
                case .success(let value):
                    swiftTool.observabilityScope.emit(error: "Failed to emit symbol graph for '\(target.c99name)': \(String(decoding: value, as: UTF8.self))")
                case .failure(let error):
                    swiftTool.observabilityScope.emit(error: "Internal error while emitting symbol graph for '\(target.c99name)': \(error)")
                }
            }
        }

        print("Files written to", symbolGraphDirectory.pathString)
    }
}

enum ExtensionBlockSymbolBehavior: String, EnumerableFlag {
    case emitExtensionBlockSymbols
    case omitExtensionBlockSymbols
}

struct DumpPackage: SwiftCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print parsed Package.swift as JSON")

    @OptionGroup(visibility: .hidden)
    var globalOptions: GlobalOptions

    func run(_ swiftTool: SwiftTool) throws {
        let workspace = try swiftTool.getActiveWorkspace()
        let root = try swiftTool.getWorkspaceRoot()

        let rootManifests = try temp_await {
            workspace.loadRootManifests(
                packages: root.packages,
                observabilityScope: swiftTool.observabilityScope,
                completion: $0
            )
        }
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

struct DumpPIF: SwiftCommand {
    // hides this command from CLI --help output
    static let configuration = CommandConfiguration(shouldDisplay: false) 

    @OptionGroup(visibility: .hidden)
    var globalOptions: GlobalOptions

    @Flag(help: "Preserve the internal structure of PIF")
    var preserveStructure: Bool = false

    func run(_ swiftTool: SwiftTool) throws {
        let graph = try swiftTool.loadPackageGraph()
        let pif = try PIFBuilder.generatePIF(
            buildParameters: swiftTool.buildParameters(),
            packageGraph: graph,
            fileSystem: swiftTool.fileSystem,
            observabilityScope: swiftTool.observabilityScope,
            preservePIFModelStructure: preserveStructure)
        print(pif)
    }

    var toolWorkspaceConfiguration: ToolWorkspaceConfiguration {
        return .init(wantsMultipleTestProducts: true)
    }
}
