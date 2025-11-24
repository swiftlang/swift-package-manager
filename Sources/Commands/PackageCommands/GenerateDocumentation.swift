//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
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
import Workspace
import SPMBuildCore
import ArgumentParserToolInfo
import SymbolKit

extension CommandInfoV0 {
  func toSymbolGraph() -> SymbolGraph {
    return SymbolGraph(
      metadata: SymbolGraph.Metadata(formatVersion: .init(major: 0, minor: 6, patch: 0), generator: "SwiftPM"),
      module: SymbolGraph.Module(name: self.commandName, platform: .init(architecture: "arm64", vendor: nil, operatingSystem: .init(name: "macOS"), environment: nil)),
      symbols: toSymbols(),
      relationships: []
    )
  }

  func toSymbols(_ path: [String] = []) -> [SymbolGraph.Symbol] {
    var symbols: [SymbolGraph.Symbol] = []

    var myPath = path
    myPath.append(self.commandName)

    guard myPath.last != "help" else {
      return []
    }

    var docComments: SymbolGraph.LineList = if let abstract = self.abstract { .init([SymbolGraph.LineList.Line(text: abstract, range: nil )]) } else { .init([]) }

    if let args = self.arguments, args.count != 0 {
      let commandString: String = myPath.joined(separator: " ")

      docComments = .init(docComments.lines + [SymbolGraph.LineList.Line(text: "```\n" + commandString + self.usage(startlength: commandString.count, wraplength: 60) + "\n```", range: nil )]) // TODO parameterize the wrap length
    }

    if let discussion = self.discussion {
      docComments = .init(docComments.lines + (discussion.split(separator: "\n").map({ SymbolGraph.LineList.Line(text: String($0), range: nil )})))
    }

    for arg in self.arguments ?? [] {
      docComments = .init(docComments.lines + [SymbolGraph.LineList.Line(text: "## \(arg.identity())\n\n\(arg.abstract ?? "")\n\n" + (arg.discussion ?? ""), range: nil)])
    }

    // TODO: Maybe someday there will be command-line semantics for the symbols and then these can be declared with more sensible categories
    symbols.append(SymbolGraph.Symbol(
      identifier: .init(precise: "s:\(myPath.joined(separator: " "))", interfaceLanguage: "swift"),
      names: .init(title: self.commandName, navigator: nil, subHeading: nil, prose: nil),
      pathComponents: myPath,
      docComment: docComments,
      accessLevel: SymbolGraph.Symbol.AccessControl(rawValue: "public"),
      kind: SymbolGraph.Symbol.Kind(parsedIdentifier: .`func`, displayName: "command"),
      mixins: [:]
    ))

    for cmd in self.subcommands ?? [] {
      symbols.append(contentsOf: cmd.toSymbols(myPath))
    }

    return symbols
  }

  /// Returns a mutl-line string that presents the arguments for a command.
  /// - Parameters:
  ///   - startlength: The starting width of the line this multi-line string appends onto.
  ///   - wraplength: The maximum width  of the multi-linecode block.
  /// - Returns: A wrapped, multi-line string that wraps the commands arguments into a text block.
  public func usage(startlength: Int, wraplength: Int) -> String {
    guard let args = self.arguments else {
      return ""
    }

    var multilineString = ""
    // This is a greedy algorithm to wrap the arguments into a
    // multi-line string that is expected to be returned within
    // a markdown code block (pre-formatted text).
    var currentLength = startlength
    for arg in args where arg.shouldDisplay {
      let nextUsage = arg.usage()
      if currentLength + arg.usage().count > wraplength {
        // the next usage() string exceeds the max width, wrap it.
        multilineString.append("\n  \(nextUsage)")
        currentLength = nextUsage.count + 2  // prepend spacing length of 2
      } else {
        // the next usage() string doesn't exceed the max width
        multilineString.append(" \(nextUsage)")
        currentLength += nextUsage.count + 1
      }
    }
    return multilineString
  }
}

extension ArgumentInfoV0 {
  /// Returns a string that describes the use of the argument.
  ///
  /// If `shouldDisplay` is `false`, an empty string is returned.
  public func usage() -> String {
    guard self.shouldDisplay else {
      return ""
    }

    let names: [String]

    if let myNames = self.names {
      names = myNames.filter { $0.kind == .long }.map(\.name)
    } else if let preferred = self.preferredName {
      names = [preferred.name]
    } else if let value = self.valueName {
      names = [value]
    } else {
      return ""
    }

    // TODO: default values, short, etc.

    var inner: String
    switch self.kind {
    case .positional:
      inner = "<\(names.joined(separator: "|"))>"
    case .option:
      inner = "--\(names.joined(separator: "|"))=<\(self.valueName ?? "")>"
    case .flag:
      inner = "--\(names.joined(separator: "|"))"
    }

    if self.isRepeating {
      inner += "..."
    }

    if self.isOptional {
      return "[\(inner)]"
    }

    return inner
  }

  public func identity() -> String {
    let names: [String]
    if let myNames = self.names {
      names = myNames.filter { $0.kind == .long }.map(\.name)
    } else if let preferred = self.preferredName {
      names = [preferred.name]
    } else if let value = self.valueName {
      names = [value]
    } else {
      return ""
    }

    // TODO: default values, values, short, etc.

    let inner: String
    switch self.kind {
    case .positional:
      inner = "\(names.joined(separator: "|"))"
    case .option:
      inner = "--\(names.joined(separator: "|"))=\\<\(self.valueName ?? "")\\>"
    case .flag:
      inner = "--\(names.joined(separator: "|"))"
    }
    return inner
  }
}

struct GenerateDocumentation: AsyncSwiftCommand {
    static let configuration = CommandConfiguration(
        abstract: "Generate documentation for a package, or targets")

    @Flag(help: .init("Generate documentation for the internal targets of the package. Otherwise, it generates only documentation for the products of the package."))
    var internalDocs: Bool = false

    @OptionGroup(visibility: .hidden)
    var globalOptions: GlobalOptions

    func run(_ swiftCommandState: SwiftCommandState) async throws {
        // TODO someday we might be able to populate the landing page with details about the package as a whole, such as traits, or even a DocC catalog that covers package-level topics

        let buildSystem = try await swiftCommandState.createBuildSystem()

        let outputs = try await buildSystem.build(subset: .allExcludingTests, buildOutputs: [
            .symbolGraph(
                .init(
                    // TODO make these all command-line parameters
                    minimumAccessLevel: .public,
                    includeInheritedDocs: true,
                    includeSynthesized: true,
                    includeSPI: true,
                    emitExtensionBlocks: true
                )
            ),
            .builtArtifacts,
        ])

        guard let symbolGraph = outputs.symbolGraph else {
            fatalError("Try again with swiftbuild build system") // FIXME - make this work with the native build system too
        }

        guard let builtArtifacts = outputs.builtArtifacts else {
            fatalError("Could not get list of built artifacts")
        }
    
        // The build system produced symbol graphs for us, one for each target.
        let buildPath = try swiftCommandState.productsBuildParameters.buildPath

        var doccArchives: [String] = []
        let doccExecutable = try swiftCommandState.toolsBuildParameters.toolchain.toolchainDir.appending(components: ["usr", "bin", "docc"])

        var modules: [ResolvedModule] = []
        var products: [ResolvedProduct] = []

        // Copy the symbol graphs from the target-specific locations to the single output directory
        for rootPackage in try await buildSystem.getPackageGraph().rootPackages {
            if !internalDocs {
                for product in rootPackage.products {
                    for module in product.modules {
                      modules.append(module)
                    }

                    products.append(product)
                }
            } else {
                modules.append(contentsOf: rootPackage.modules)
                products.append(contentsOf: rootPackage.products)
            }
        }

        for product in products {
          if product.type == .executable {
              let doccCatalogDir = product.modules.first?.underlying.others.filter({ $0.extension?.lowercased() == "docc" }).first
              var symbolGraphDir: AbsolutePath? = nil

              if let exec = builtArtifacts.filter({ $0.1.kind == .executable && $0.0 == "\(product.name)-product" }).first?.1.path {
              do {
                  // FIXME run the executable within a very restricted sandbox
                  let dumpHelpProcess = AsyncProcess(args: [exec, "--experimental-dump-help"], outputRedirection: .collect)
                  try dumpHelpProcess.launch()
                  let result = try await dumpHelpProcess.waitUntilExit()
                  let output = try result.utf8Output()
                  let toolInfo = try JSONDecoder().decode(ToolInfoV0.self, from: output)

                  // Creating a symbol graph that represents the command-line structure
                  symbolGraphDir = buildPath.appending(components: ["tool-symbol-graph", product.name])
                  guard let graphDir = symbolGraphDir else {fatalError()}

                  try? swiftCommandState.fileSystem.removeFileTree(graphDir)
                  try swiftCommandState.fileSystem.createDirectory(graphDir, recursive: true)
                  
                  let graph = toolInfo.command.toSymbolGraph()
                  let doc = try JSONEncoder().encode(graph)
                  let graphFile = graphDir.appending(components: ["\(product.name).symbols.json"])
                  try swiftCommandState.fileSystem.writeFileContents(graphFile, data: doc)
              } catch {
                  print("warning: could not generate tool info documentation for \(product.name)")
              }
            }

            guard doccCatalogDir != nil || symbolGraphDir != nil else {
              print("Skipping \(product.name) because there is no DocC catalog and there is no symbol graph that could be generated for it. You can add your own documentation for this executable product by adding a documentation directory with the '.docc' file extension and your own DocC formatted markdown files in the module for this product.")
              continue
            }

            let catalogArgs = if let doccCatalogDir  {[doccCatalogDir.pathString]} else {[String]()}
            let graphArgs = if let symbolGraphDir {["--additional-symbol-graph-dir=\(symbolGraphDir)"]} else {[String]()}

            print("CONVERTING: \(product.name)")

            let archiveDir = buildPath.appending(components: ["tool-docc-archive", "\(product.name).doccarchive"])
            try? swiftCommandState.fileSystem.removeFileTree(archiveDir)
            try swiftCommandState.fileSystem.createDirectory(archiveDir.parentDirectory, recursive: true)
    
            let process = try Process.run(URL(fileURLWithPath: doccExecutable.pathString), arguments: [
                "convert",
                ] + catalogArgs + [
                "--fallback-display-name=\(product.name)",
                "--fallback-bundle-identifier=\(product.name)",
                ] + graphArgs + [
                "--output-path=\(archiveDir)",
            ])
            process.waitUntilExit()

            if swiftCommandState.fileSystem.exists(archiveDir) {
                print("SUCCESS!")
                doccArchives.append(archiveDir.pathString)
            }
          }
        }

        for module: ResolvedModule in modules {
            let symbolGraphDir = symbolGraph.outputLocationForTarget(module.name, try swiftCommandState.productsBuildParameters)
            let symbolGraphPath = buildPath.appending(components: symbolGraphDir)

            // The DocC catalog for this module is any directory with the docc file extension
            let doccCatalogDir = module.underlying.others.first { sourceFile in
                return sourceFile.extension?.lowercased() == "docc"
            }

            guard doccCatalogDir != nil || swiftCommandState.fileSystem.exists(symbolGraphPath) else {
              print("Skipping \(module.name) because there is no DocC catalog and there is no symbol graph that could be generated for it. You can write your own documentation for this target by creating a directory with a '.docc' file extension and adding DocC formatted markdown files.")
              continue
            }

            let catalogArgs = if let doccCatalogDir {[doccCatalogDir.pathString]} else {[String]()}
            let graphArgs = if swiftCommandState.fileSystem.exists(symbolGraphPath) {["--additional-symbol-graph-dir=\(symbolGraphPath)"]} else {[String]()}

            print("CONVERTING: \(module.name)")

            let archiveDir = buildPath.appending(components: ["module-docc-archive", "\(module.name).doccarchive"])
            try? swiftCommandState.fileSystem.removeFileTree(archiveDir)
            try swiftCommandState.fileSystem.createDirectory(archiveDir.parentDirectory, recursive: true)

            let process = try Process.run(URL(fileURLWithPath: doccExecutable.pathString), arguments: [
                "convert",
                ] + catalogArgs + [
                "--fallback-display-name=\(module.name)",
                "--fallback-bundle-identifier=\(module.name)",
                ] + graphArgs + [
                "--output-path=\(archiveDir)",
            ])
            process.waitUntilExit()

            if swiftCommandState.fileSystem.exists(archiveDir) {
                doccArchives.append(archiveDir.pathString)
            }
        }

        guard doccArchives.count > 0 else {
            print("No modules are available to document.")
            return
        }

        let packageName = try await buildSystem.getPackageGraph().rootPackages.first!.identity.description
        let outputPath = buildPath.appending(components: ["Swift-DocC", packageName])

        try? swiftCommandState.fileSystem.removeFileTree(outputPath) // docc merge requires an empty output directory
        try swiftCommandState.fileSystem.createDirectory(outputPath, recursive: true)

        print("MERGE: \(doccArchives)")

        let process = try Process.run(URL(fileURLWithPath: doccExecutable.pathString), arguments: [
                    "merge",
                    "--synthesized-landing-page-name=\(packageName)",
                    "--synthesized-landing-page-kind=Package",
                ] + doccArchives + [
                    "--output-path=\(outputPath)"
                ])
        process.waitUntilExit()

        // TODO provide an option to set up an http server
        print("python3 -m http.server --directory \(outputPath)")
        print("http://localhost:8000/documentation")
      }
}
