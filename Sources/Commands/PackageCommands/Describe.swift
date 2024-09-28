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

import struct TSCBasic.StringError

extension SwiftPackageCommand {
    struct Describe: AsyncSwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Describe the current package")
        
        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions
        
        @Option(help: "json | text | mermaid")
        var type: DescribeMode = .text
        
        func run(_ swiftCommandState: SwiftCommandState) async throws {
            let workspace = try swiftCommandState.getActiveWorkspace()
            
            guard let packagePath = try swiftCommandState.getWorkspaceRoot().packages.first else {
                throw StringError("unknown package")
            }
            
            let package = try await workspace.loadRootPackage(
                at: packagePath,
                observabilityScope: swiftCommandState.observabilityScope
            )

            let buildSystem = try await swiftCommandState.createBuildSystem(
                // We are enabling all traits for finding the root package executables.
                traitConfiguration: .init(enableAllTraits: true)
            )

            let packageGraph = try await buildSystem.getPackageGraph()

            let rootPackages = packageGraph.rootPackages.map { $0.identity }

            let executables = packageGraph.allProducts.filter({
                $0.type == .executable || $0.type == .snippet
            }).map { product -> (package: String?, name: String) in
                if !rootPackages.contains(product.packageIdentity) {
                    return (package: product.packageIdentity.description, name: product.name)
                } else {
                    return (package: Optional<String>.none, name: product.name)
                }
            }

            try self.describe(package, executables: Array(executables), in: type)
        }
        
        /// Emits a textual description of `package` to `stream`, in the format indicated by `mode`.
        func describe(_ package: Package, executables: [(package: String?, name: String)], in mode: DescribeMode) throws {
            let desc = DescribedPackage(from: package, executables: executables)
            let data: Data
            switch mode {
            case .json:
                let encoder = JSONEncoder.makeWithDefaults()
                encoder.keyEncodingStrategy = .convertToSnakeCase
                data = try encoder.encode(desc)
            case .text:
                var encoder = PlainTextEncoder()
                encoder.formattingOptions = [.prettyPrinted]
                data = try encoder.encode(desc)
            case .mermaid:
                data = Data(MermaidPackageSerializer(package: package).renderedMarkdown.utf8)
            }
            print(String(decoding: data, as: UTF8.self))
        }
        
        enum DescribeMode: String, ExpressibleByArgument {
            /// JSON format (guaranteed to be parsable and stable across time).
            case json
            /// Human readable format (not guaranteed to be parsable).
            case text
            /// Mermaid flow charts format
            case mermaid
        }
    }
}
