//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
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

struct ShowExecutables: AsyncSwiftCommand {
    static let configuration = CommandConfiguration(
        abstract: "List the available executables from this package.")

    @OptionGroup(visibility: .hidden)
    var globalOptions: GlobalOptions

    @Option(help: "Set the output format.")
    var format: ShowExecutablesMode = .flatlist

    func run(_ swiftCommandState: SwiftCommandState) async throws {
        let packageGraph = try await swiftCommandState.loadPackageGraph()
        let rootPackages = packageGraph.rootPackages.map { $0.identity }

        let executables = packageGraph.allProducts.filter({
            $0.type == .executable || $0.type == .snippet
        }).map { product -> Executable in
            if !rootPackages.contains(product.packageIdentity) {
                return Executable(package: product.packageIdentity.description, name: product.name)
            } else {
                return Executable(package: Optional<String>.none, name: product.name)
            }
        }.sorted(by: {$0.name < $1.name})

        switch self.format {
        case .flatlist:
            for executable in executables {
                if let package = executable.package {
                    print("\(executable.name) (\(package))")
                } else {
                    print(executable.name)
                }
            }

        case .json:
            let encoder = JSONEncoder()
            let data = try encoder.encode(executables)
            if let output = String(data: data, encoding: .utf8) {
                print(output)
            }
        }
    }

    struct Executable: Codable {
        var package: String?
        var name: String
    }

    enum ShowExecutablesMode: String, RawRepresentable, CustomStringConvertible, ExpressibleByArgument, CaseIterable {
        case flatlist, json

        public init?(rawValue: String) {
            switch rawValue.lowercased() {
            case "flatlist":
                self = .flatlist
            case "json":
                self = .json
            default:
                return nil
            }
        }

        public var description: String {
            switch self {
            case .flatlist: return "flatlist"
            case .json: return "json"
            }
        }
    }
}
