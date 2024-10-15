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
import PackageGraph

import class TSCBasic.LocalFileOutputByteStream
import protocol TSCBasic.OutputByteStream
import var TSCBasic.stdoutStream

extension SwiftPackageCommand {
    struct ShowDependencies: AsyncSwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print the resolved dependency graph")

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Option(help: "Set the output format")
        var format: ShowDependenciesMode = .text

        @Option(name: [.long, .customShort("o") ],
                help: "The absolute or relative path to output the resolved dependency graph.")
        var outputPath: AbsolutePath?

        func run(_ swiftCommandState: SwiftCommandState) async throws {
            let graph = try await swiftCommandState.loadPackageGraph()
            // command's result output goes on stdout
            // ie "swift package show-dependencies" should output to stdout
            let stream: OutputByteStream = try outputPath.map { try LocalFileOutputByteStream($0) } ?? TSCBasic.stdoutStream
            Self.dumpDependenciesOf(
                graph: graph,
                rootPackage: graph.rootPackages[graph.rootPackages.startIndex],
                mode: format,
                on: stream
            )
        }

        static func dumpDependenciesOf(
            graph: ModulesGraph,
            rootPackage: ResolvedPackage,
            mode: ShowDependenciesMode,
            on stream: OutputByteStream
        ) {
            let dumper: DependenciesDumper
            switch mode {
            case .text:
                dumper = PlainTextDumper()
            case .dot:
                dumper = DotDumper()
            case .json:
                dumper = JSONDumper()
            case .flatlist:
                dumper = FlatListDumper()
            }
            dumper.dump(graph: graph, dependenciesOf: rootPackage, on: stream)
            stream.flush()
        }

        enum ShowDependenciesMode: String, RawRepresentable, CustomStringConvertible, ExpressibleByArgument, CaseIterable {
            case text, dot, json, flatlist

            public init?(rawValue: String) {
                switch rawValue.lowercased() {
                case "text":
                    self = .text
                case "dot":
                    self = .dot
                case "json":
                    self = .json
                case "flatlist":
                    self = .flatlist
                default:
                    return nil
                }
            }

            public var description: String {
                switch self {
                case .text: return "text"
                case .dot: return "dot"
                case .json: return "json"
                case .flatlist: return "flatlist"
                }
            }
        }
    }
}
