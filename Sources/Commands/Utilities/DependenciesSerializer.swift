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
    func dump(graph: ModulesGraph, dependenciesOf: ResolvedPackage, on: OutputByteStream)
}

final class PlainTextDumper: DependenciesDumper {
    func dump(graph: ModulesGraph, dependenciesOf rootpkg: ResolvedPackage, on stream: OutputByteStream) {
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

                stream.send("\(hanger)\(package.identity.description)<\(package.manifest.packageLocation)@\(pkgVersion)>\(traitsEnabled)\n")

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
    func dump(graph: ModulesGraph, dependenciesOf rootpkg: ResolvedPackage, on stream: OutputByteStream) {
        func recursiveWalk(packages: [ResolvedPackage]) {
            for package in packages {
                stream.send(package.identity.description).send("\n")
                if !package.dependencies.isEmpty {
                    recursiveWalk(packages: graph.directDependencies(for: package))
                }
            }
        }
        if !rootpkg.dependencies.isEmpty {
            recursiveWalk(packages: graph.directDependencies(for: rootpkg))
        }
    }
}

final class DotDumper: DependenciesDumper {
    /// Escapes a string for use inside a double-quoted DOT identifier or label.
    ///
    /// Graphviz uses the backslash as an escape introducer, so a literal backslash has to be
    /// doubled and a double quote has to be escaped. Package locations are file system paths for
    /// root, file system and local source control packages, which on Windows contain backslashes:
    /// without this, a location such as `C:\Users\New` has `\N` substituted with the node name in
    /// the label, and a location ending in a path separator escapes the closing quote and makes the
    /// whole graph unparsable.
    static func escapedForDOT(_ string: String) -> String {
        // The backslash has to be escaped first, otherwise the backslashes introduced when escaping
        // the double quotes would be escaped a second time.
        string.replacing("\\", with: "\\\\")
            .replacing("\"", with: "\\\"")
    }

    func dump(graph: ModulesGraph, dependenciesOf rootpkg: ResolvedPackage, on stream: OutputByteStream) {
        var nodesAlreadyPrinted: Set<String> = []
        func printNode(_ package: ResolvedPackage) {
            let url = package.manifest.packageLocation
            if nodesAlreadyPrinted.contains(url) { return }
            let pkgVersion = package.manifest.version?.description ?? "unspecified"
            let escapedURL = Self.escapedForDOT(url)
            let escapedIdentity = Self.escapedForDOT(package.identity.description)
            let escapedVersion = Self.escapedForDOT(pkgVersion)
            stream.send(#""\#(escapedURL)" [label="\#(escapedIdentity)\n\#(escapedURL)\n\#(escapedVersion)"]"#)
                .send("\n")
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
                stream.send(#""\#(Self.escapedForDOT(rootURL))" -> "\#(Self.escapedForDOT(dependencyURL))""#)
                    .send("\n")
                dependenciesAlreadyPrinted.insert(urlPair)

                if !dependency.dependencies.isEmpty {
                    recursiveWalk(rootpkg: dependency)
                }
            }
        }

        if !rootpkg.dependencies.isEmpty {
            stream.send(
                """
                digraph DependenciesGraph {
                node [shape = box]

                """
            )
            recursiveWalk(rootpkg: rootpkg)
            stream.send("}\n")
        } else {
            stream.send("No external dependencies found\n")
        }
    }
}

final class JSONDumper: DependenciesDumper {
    func dump(graph: ModulesGraph, dependenciesOf rootpkg: ResolvedPackage, on stream: OutputByteStream) {
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

        stream.send("\(convert(rootpkg).toString(prettyPrint: true))\n")
    }
}
