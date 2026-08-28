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
import Foundation
import PackageModel
import PackageGraph
import Workspace

import struct TSCBasic.StringError

extension SwiftPackageCommand {
    struct Describe: AsyncSwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Describe the current package.",
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)]
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Option(help: "Set the output format.")
        var type: DescribeMode = .text

        /// Restricts the output to the named workspace member.
        /// Overrides an implicit CWD-inside-member focus. Outside a
        /// workspace the flag has no effect (only one root package
        /// exists). Same shape as Slice 5's `swift build --package`
        /// selector and Slice 10's `show-dependencies --package`.
        @Option(
            name: .customLong("package"),
            help: "Restrict the description to the named workspace member.",
        )
        var selectedPackage: PackageIdentity?

        func run(_ swiftCommandState: SwiftCommandState) async throws {
            let graph = try await swiftCommandState.loadPackageGraph()
            guard let scopedRoots = Self.scopedRootPackages(
                allRoots: Array(graph.rootPackages),
                selectedPackage: self.selectedPackage,
                workspaceMemberFocus: swiftCommandState.currentWorkspaceMemberFocus,
                observabilityScope: swiftCommandState.observabilityScope,
            ) else {
                throw ExitCode.failure
            }
            try self.describe(scopedRoots.map(\.underlying), in: self.type)
        }

        /// Emits a description of `packages` in the requested format.
        ///
        /// - text: when more than one member is in scope, each member
        ///   is preceded by a `--- <identity> ---` header and a blank
        ///   line separator. Single-member output stays unheadered so
        ///   non-workspace usage is byte-identical to pre-Slice-13.
        /// - json: multi-member output is a JSON array of per-member
        ///   `DescribedPackage` objects; single-member output is a
        ///   single top-level object (backwards-compat with tooling
        ///   that consumes `swift package describe --type json`).
        /// - mermaid: per-member diagrams concatenated by a blank
        ///   line. Single-member output unchanged.
        func describe(_ packages: [Package], in mode: DescribeMode) throws {
            switch mode {
            case .json:
                try self.emitJSON(packages)
            case .text:
                try self.emitText(packages)
            case .mermaid:
                self.emitMermaid(packages)
            }
        }

        private func emitJSON(_ packages: [Package]) throws {
            let encoder = JSONEncoder.makeWithDefaults()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let descs = packages.map(DescribedPackage.init(from:))
            let data: Data
            if descs.count == 1, let only = descs.first {
                data = try encoder.encode(only)
            } else {
                data = try encoder.encode(descs)
            }
            print(String(decoding: data, as: UTF8.self))
        }

        private func emitText(_ packages: [Package]) throws {
            var encoder = PlainTextEncoder()
            encoder.formattingOptions = [.prettyPrinted]
            let multi = packages.count > 1
            for (index, package) in packages.enumerated() {
                if multi {
                    if index > 0 {
                        print("")
                    }
                    print("--- \(package.identity) ---")
                    print("")
                }
                let data = try encoder.encode(DescribedPackage(from: package))
                print(String(decoding: data, as: UTF8.self))
            }
        }

        private func emitMermaid(_ packages: [Package]) {
            for (index, package) in packages.enumerated() {
                if index > 0 {
                    print("")
                }
                print(MermaidPackageSerializer(package: package).renderedMarkdown)
            }
        }

        /// Filters the loaded graph's root packages to the in-scope
        /// subset. Priority order (highest first):
        /// 1. Explicit `--package <id>` — hard-select. Missing
        ///    identity emits `.unknownWorkspaceMember` and returns
        ///    `nil` so the caller can abort.
        /// 2. Case A CWD focus — soft-select when the focus matches
        ///    a root; falls through otherwise so the user still sees
        ///    something meaningful.
        /// 3. All roots — the workspace-root default.
        ///
        /// Duplicated verbatim from
        /// `ShowDependencies.scopedRootPackages` — extracting to a
        /// shared helper is a follow-up when a third caller appears.
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

        enum DescribeMode: String, ExpressibleByArgument, CaseIterable {
            /// JSON format (guaranteed to be parsable and stable across time).
            case json
            /// Human readable format (not guaranteed to be parsable).
            case text
            /// Mermaid flow charts format
            case mermaid
        }
    }
}
