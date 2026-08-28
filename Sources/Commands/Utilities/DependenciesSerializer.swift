//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import PackageModel
import PackageGraph
import TSCUtility

import enum TSCBasic.JSON
import protocol TSCBasic.OutputByteStream

protocol DependenciesDumper {
    func dump(graph: ModulesGraph, dependenciesOf: [ResolvedPackage], on: OutputByteStream)
}

final class PlainTextDumper: DependenciesDumper {
    func dump(graph: ModulesGraph, dependenciesOf rootPackages: [ResolvedPackage], on stream: OutputByteStream) {
        for (index, rootPackage) in rootPackages.enumerated() {
            if rootPackages.count > 1 {
                if index > 0 {
                    stream.send("\n")
                }
                stream.send("--- \(rootPackage.identity.description) ---\n")
            }
            self.dumpSingleRoot(graph: graph, dependenciesOf: rootPackage, on: stream)
        }
    }

    private func dumpSingleRoot(graph: ModulesGraph, dependenciesOf rootpkg: ResolvedPackage, on stream: OutputByteStream) {
        func recursiveWalk(packages: [ResolvedPackage], prefix: String = "") {
            var hanger = prefix + "├── "

            for (index, package) in packages.enumerated() {
                if index == packages.count - 1 {
                    hanger = prefix + "└── "
                }

                let pkgVersion = package.manifest.version?.description ?? "unspecified"

                let traitsEnabled: String
                if let enabled = package.enabledTraits, !enabled.isEmpty {
                    traitsEnabled = "(traits: \(package.enabledTraits?.joined(separator: ", ") ?? ""))"
                } else {
                    traitsEnabled = ""
                }

                let workspaceMemberTag = graph.isWorkspaceMember(package) ? " [workspace member]" : ""

                stream.send("\(hanger)\(package.identity.description)<\(package.manifest.packageLocation)@\(pkgVersion)>\(traitsEnabled)\(workspaceMemberTag)\n")

                if !package.dependencies.isEmpty {
                    let replacement = (index == packages.count - 1) ?  "    " : "│   "
                    var childPrefix = hanger
                    let startIndex = childPrefix.index(childPrefix.endIndex, offsetBy: -4)
                    childPrefix.replaceSubrange(startIndex..<childPrefix.endIndex, with: replacement)
                    recursiveWalk(packages: graph.directDependencies(for: package), prefix: childPrefix)
                }
            }
        }

        if !rootpkg.dependencies.isEmpty {
            stream.send(".\n")
            recursiveWalk(packages: graph.directDependencies(for: rootpkg))
        } else {
            stream.send("No external dependencies found\n")
        }
    }
}

final class FlatListDumper: DependenciesDumper {
    func dump(graph: ModulesGraph, dependenciesOf rootPackages: [ResolvedPackage], on stream: OutputByteStream) {
        var emitted: Set<String> = []
        func recursiveWalk(packages: [ResolvedPackage]) {
            for package in packages {
                let identity = package.identity.description
                if emitted.insert(identity).inserted {
                    stream.send(identity).send("\n")
                }
                if !package.dependencies.isEmpty {
                    recursiveWalk(packages: graph.directDependencies(for: package))
                }
            }
        }
        for rootpkg in rootPackages where !rootpkg.dependencies.isEmpty {
            recursiveWalk(packages: graph.directDependencies(for: rootpkg))
        }
    }
}

final class DotDumper: DependenciesDumper {
    func dump(graph: ModulesGraph, dependenciesOf rootPackages: [ResolvedPackage], on stream: OutputByteStream) {
        let rootsWithDeps = rootPackages.filter { !$0.dependencies.isEmpty }
        guard !rootsWithDeps.isEmpty else {
            stream.send("No external dependencies found\n")
            return
        }

        var nodesAlreadyPrinted: Set<String> = []
        func printNode(_ package: ResolvedPackage) {
            let url = package.manifest.packageLocation
            if nodesAlreadyPrinted.contains(url) { return }
            let pkgVersion = package.manifest.version?.description ?? "unspecified"
            stream.send(#""\#(url)" [label="\#(package.identity.description)\n\#(url)\n\#(pkgVersion)"]"#).send("\n")
            nodesAlreadyPrinted.insert(url)
        }

        struct DependencyURLs: Hashable {
            var root: String
            var dependency: String
        }
        var dependenciesAlreadyPrinted: Set<DependencyURLs> = []
        func recursiveWalk(rootpkg: ResolvedPackage) {
            printNode(rootpkg)
            for dependency in graph.directDependencies(for: rootpkg) {
                let rootURL = rootpkg.manifest.packageLocation
                let dependencyURL = dependency.manifest.packageLocation
                let urlPair = DependencyURLs(root: rootURL, dependency: dependencyURL)
                if dependenciesAlreadyPrinted.contains(urlPair) { continue }

                printNode(dependency)
                stream.send(#""\#(rootURL)" -> "\#(dependencyURL)""#).send("\n")
                dependenciesAlreadyPrinted.insert(urlPair)

                if !dependency.dependencies.isEmpty {
                    recursiveWalk(rootpkg: dependency)
                }
            }
        }

        stream.send(
            """
            digraph DependenciesGraph {
            node [shape = box]

            """
        )
        let wrapInCluster = rootsWithDeps.count > 1
        for rootpkg in rootsWithDeps {
            if wrapInCluster {
                let clusterID = Self.sanitizeForDotClusterID(rootpkg.identity.description)
                stream.send(#"subgraph cluster_\#(clusterID) {"#).send("\n")
                stream.send(#"label = "\#(rootpkg.identity.description)""#).send("\n")
            }
            recursiveWalk(rootpkg: rootpkg)
            if wrapInCluster {
                stream.send("}\n")
            }
        }
        stream.send("}\n")
    }

    /// Sanitizes a package identity into a DOT-compatible cluster
    /// identifier. DOT IDs must be `[a-zA-Z0-9_]+`; identities with
    /// hyphens (e.g. `some-lib`) or other punctuation would be a syntax
    /// error inside `subgraph cluster_<id> { ... }`.
    static func sanitizeForDotClusterID(_ identity: String) -> String {
        String(identity.map { char in
            (char.isASCII && (char.isLetter || char.isNumber || char == "_")) ? char : "_"
        })
    }
}

final class JSONDumper: DependenciesDumper {
    func dump(graph: ModulesGraph, dependenciesOf rootPackages: [ResolvedPackage], on stream: OutputByteStream) {
        func convert(_ package: ResolvedPackage) -> JSON {
            return .orderedDictionary([
                "identity": .string(package.identity.description),
                "name": .string(package.manifest.displayName), // TODO: remove?
                "url": .string(package.manifest.packageLocation),
                "version": .string(package.manifest.version?.description ?? "unspecified"),
                "path": .string(package.path.pathString),
                "traits": .array(package.enabledTraits?.map { .string($0) } ?? []),
                "dependencies": .array(package.dependencies.compactMap { graph.packages[$0] }.map(convert)),
            ])
        }

        // Single-root output preserves the pre-workspaces top-level
        // object shape so existing tooling that consumes it keeps
        // working. Multi-root wraps the per-root objects in an array.
        let payload: JSON
        if rootPackages.count == 1, let only = rootPackages.first {
            payload = convert(only)
        } else {
            payload = .array(rootPackages.map(convert))
        }
        stream.send("\(payload.toString(prettyPrint: true))\n")
    }
}
