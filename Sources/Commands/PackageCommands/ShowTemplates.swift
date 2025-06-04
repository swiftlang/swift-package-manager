//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2025 Apple Inc. and the Swift project authors
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

struct ShowTemplates: AsyncSwiftCommand {
    static let configuration = CommandConfiguration(
        abstract: "List the available executables from this package.")

    @OptionGroup(visibility: .hidden)
    var globalOptions: GlobalOptions

    @Option(help: "Set the output format.")
    var format: ShowTemplatesMode = .flatlist

    func run(_ swiftCommandState: SwiftCommandState) async throws {
        let packageGraph = try await swiftCommandState.loadPackageGraph()
        let rootPackages = packageGraph.rootPackages.map { $0.identity }

        let templates = packageGraph.allModules.filter({
            $0.type == .template || $0.type == .snippet
        }).map { module -> Template in
            if !rootPackages.contains(module.packageIdentity) {
                return Template(package: module.packageIdentity.description, name: module.name)
            } else {
                return Template(package: Optional<String>.none, name: module.name)
            }
        }

        switch self.format {
        case .flatlist:
            for template in templates.sorted(by: {$0.name < $1.name }) {
                if let package = template.package {
                    print("\(template.name) (\(package))")
                } else {
                    print(template.name)
                }
            }

        case .json:
            let encoder = JSONEncoder()
            let data = try encoder.encode(templates)
            if let output = String(data: data, encoding: .utf8) {
                print(output)
            }
        }
    }

    struct Template: Codable {
        var package: String?
        var name: String
    }

    enum ShowTemplatesMode: String, RawRepresentable, CustomStringConvertible, ExpressibleByArgument, CaseIterable {
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
