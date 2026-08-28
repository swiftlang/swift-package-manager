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
@_spi(SwiftPMInternal) import CoreCommands
import PackageGraph
import PackageModel

import class TSCBasic.LocalFileOutputByteStream
import protocol TSCBasic.OutputByteStream
import var TSCBasic.stdoutStream

extension SwiftPackageCommand {
    struct ShowDependencies: AsyncSwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print the resolved dependency graph.",
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)]
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Option(help: "Set the output format.")
        var format: ShowDependenciesMode = .text

        @Option(name: [.long, .customShort("o") ],
                help: "The absolute or relative path to output the resolved dependency graph.")
        var outputPath: AbsolutePath?

        /// Selects a specific workspace member by identity. Overrides
        /// Case A (CWD-inside-member focus) and the workspace-root
        /// all-members default. If the identity is not a workspace
        /// member, an error diagnostic is emitted.
        @Option(
            name: .customLong("package"),
            help: "Select a specific workspace member by identity.",
        )
        var selectedPackage: PackageIdentity?

        func run(_ swiftCommandState: SwiftCommandState) async throws {
            let graph = try await swiftCommandState.loadPackageGraph()
            // command's result output goes on stdout
            // ie "swift package show-dependencies" should output to stdout
            let stream: OutputByteStream = try outputPath.map { try LocalFileOutputByteStream($0) } ?? TSCBasic.stdoutStream
            guard let scopedRoots = Self.scopedRootPackages(
                allRoots: Array(graph.rootPackages),
                selectedPackage: self.selectedPackage,
                workspaceMemberFocus: swiftCommandState.currentWorkspaceMemberFocus,
                observabilityScope: swiftCommandState.observabilityScope,
            ) else {
                throw ExitCode.failure
            }
            Self.dumpDependenciesOf(
                graph: graph,
                rootPackages: scopedRoots,
                mode: format,
                on: stream
            )
        }

        /// Filters the loaded graph's root packages to the in-scope
        /// subset. Priority order (highest first):
        /// 1. Explicit `--package <id>` — hard-select. Missing identity
        ///    emits `.unknownWorkspaceMember` and returns `nil` so the
        ///    caller can abort.
        /// 2. Case A CWD focus — soft-select when the focus matches a
        ///    root; falls through otherwise so the user still sees
        ///    something meaningful.
        /// 3. All roots — the workspace-root default.
        static func scopedRootPackages(
            allRoots: [ResolvedPackage],
            selectedPackage: PackageIdentity?,
            workspaceMemberFocus: PackageIdentity?,
            observabilityScope: ObservabilityScope,
        ) -> [ResolvedPackage]? {
            if let selectedPackage {
                if let match = allRoots.first(where: { $0.identity == selectedPackage }) {
                    return [match]
                }
                let known = Set(allRoots.map(\.identity))
                observabilityScope.emit(
                    .unknownWorkspaceMember(requested: selectedPackage, known: known),
                )
                return nil
            }
            if let focus = workspaceMemberFocus,
               let focused = allRoots.first(where: { $0.identity == focus })
            {
                return [focused]
            }
            return allRoots
        }

        static func dumpDependenciesOf(
            graph: ModulesGraph,
            rootPackages: [ResolvedPackage],
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
            dumper.dump(graph: graph, dependenciesOf: rootPackages, on: stream)
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
