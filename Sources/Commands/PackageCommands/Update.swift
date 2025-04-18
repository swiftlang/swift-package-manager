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
import Dispatch
import PackageModel
import PackageGraph
import Workspace

extension SwiftPackageCommand {
    struct Update: AsyncSwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Update package dependencies")
        
        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions
        
        @Flag(name: [.long, .customShort("n")],
              help: "Display the list of dependencies that can be updated")
        var dryRun: Bool = false
        
        @Argument(help: "The packages to update")
        var packages: [String] = []
        
        func run(_ swiftCommandState: SwiftCommandState) async throws {
            let workspace = try swiftCommandState.getActiveWorkspace()
            
            let changes = try await workspace.updateDependencies(
                root: swiftCommandState.getWorkspaceRoot(),
                packages: packages,
                dryRun: dryRun,
                observabilityScope: swiftCommandState.observabilityScope
            )

            if self.dryRun, let changes = changes, let resolvedPackagesStore = swiftCommandState.observabilityScope.trap({ try workspace.resolvedPackagesStore.load() }){
                self.logPackageChanges(changes: changes, store: resolvedPackagesStore)
            }
            
            if !self.dryRun {
                // Throw if there were errors when loading the graph.
                // The actual errors will be printed before exiting.
                guard !swiftCommandState.observabilityScope.errorsReported else {
                    throw ExitCode.failure
                }
            }
        }
        
        private func logPackageChanges(changes: [(PackageReference, Workspace.PackageStateChange)], store: ResolvedPackagesStore) {
            let changes = changes.filter { $0.1 != .unchanged }
            
            var report = "\(changes.count) dependenc\(changes.count == 1 ? "y has" : "ies have") changed\(changes.count > 0 ? ":" : ".")"
            for (package, change) in changes {
                let currentVersion = store.resolvedPackages[package.identity]?.state.description ?? ""
                switch change {
                case let .added(state):
                    report += "\n"
                    report += "+ \(package.identity) \(state.requirement.prettyPrinted)"
                case let .updated(state):
                    report += "\n"
                    report += "~ \(package.identity) \(currentVersion) -> \(package.identity) \(state.requirement.prettyPrinted)"
                case .removed:
                    report += "\n"
                    report += "- \(package.identity) \(currentVersion)"
                case .unchanged:
                    continue
                }
            }
            
            print(report)
        }
    }
}
