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

struct ShowTraits: AsyncSwiftCommand {
    static let configuration = CommandConfiguration(
        abstract: "List the available traits for a package.",
        helpNames: [.short, .long, .customLong("help", withSingleDash: true)]
    )

    @OptionGroup(visibility: .hidden)
    var globalOptions: GlobalOptions

    @Option(help: "Show traits for any package id in the transitive dependencies.")
    var packageId: String?

    @Option(help: "Set the output format.")
    var format: ShowTraitsMode = .text

    func run(_ swiftCommandState: SwiftCommandState) async throws {
        let packageGraph = try await swiftCommandState.loadPackageGraph()

        let traits = if let packageId {
            packageGraph.packages.filter({ $0.identity.description == packageId }).flatMap( { $0.manifest.traits } ).sorted(by: {$0.name < $1.name} )
        } else {
            packageGraph.rootPackages.flatMap( { $0.manifest.traits } ).sorted(by: {$0.name < $1.name} )
        }

        switch self.format {
        case .text:
            let defaultTraits = traits.filter( { $0.isDefault } ).flatMap( { $0.enabledTraits })

            for trait in traits {
                guard !trait.isDefault else {
                    continue
                }

                print("\(trait.name)\(trait.description ?? "" != "" ? " - " + trait.description! : "")\(defaultTraits.contains(trait.name) ? " (default)" : "")")
            }

        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys

            let data = try encoder.encode(traits)
            if let output = String(data: data, encoding: .utf8) {
                print(output)
            }
        }
    }

    enum ShowTraitsMode: String, RawRepresentable, CustomStringConvertible, ExpressibleByArgument, CaseIterable {
        case text, json

        public init?(rawValue: String) {
            switch rawValue.lowercased() {
            case "text":
                self = .text
            case "json":
                self = .json
            default:
                return nil
            }
        }

        public var description: String {
            switch self {
            case .text: return "text"
            case .json: return "json"
            }
        }
    }
}
