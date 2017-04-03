/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageModel

func dumpDependenciesOf(rootPackage: ResolvedPackage, mode: ShowDependenciesMode) {
    let dumper: DependenciesDumper
    switch mode {
    case .text:
        dumper = PlainTextDumper()
    case .dot:
        dumper = DotDumper()
    case .json:
        dumper = JSONDumper()
    }
    dumper.dump(dependenciesOf: rootPackage)
}

private protocol DependenciesDumper {
    func dump(dependenciesOf: ResolvedPackage)
}

private final class PlainTextDumper: DependenciesDumper {
    func dump(dependenciesOf rootpkg: ResolvedPackage) {
        func recursiveWalk(packages: [ResolvedPackage], prefix: String = "") {
            var hanger = prefix + "├── "

            for (index, package) in packages.enumerated() {
                if index == packages.count - 1 {
                    hanger = prefix + "└── "
                }

                let pkgVersion = package.manifest.version?.description ?? "unspecified"

                print("\(hanger)\(package.name)<\(package.manifest.url)@\(pkgVersion)>")

                if !package.dependencies.isEmpty {
                    let replacement = (index == packages.count - 1) ?  "    " : "│   "
                    var childPrefix = hanger
                    let startIndex = childPrefix.index(childPrefix.endIndex, offsetBy: -4)
                    childPrefix.replaceSubrange(startIndex..<childPrefix.endIndex, with: replacement)
                    recursiveWalk(packages: package.dependencies, prefix: childPrefix)
                }
            }
        }

        if !rootpkg.dependencies.isEmpty {
            print(".")
            recursiveWalk(packages: rootpkg.dependencies)
        } else {
            print("No external dependencies found")
        }
    }
}

private final class DotDumper: DependenciesDumper {
    func dump(dependenciesOf rootpkg: ResolvedPackage) {
        func recursiveWalk(rootpkg: ResolvedPackage) {
            printNode(rootpkg)
            for dependency in rootpkg.dependencies {
                printNode(dependency)
                print("\"\(rootpkg.manifest.url)\" -> \"\(dependency.manifest.url)\"")

                if !dependency.dependencies.isEmpty {
                    recursiveWalk(rootpkg: dependency)
                }
            }
        }

        func printNode(_ package: ResolvedPackage) {
            let pkgVersion = package.manifest.version?.description ?? "unspecified"
            print("\"\(package.manifest.url)\"[label=\"\(package.name)\\n\(package.manifest.url)\\n\(pkgVersion)\"]")
        }

        if !rootpkg.dependencies.isEmpty {
            print("digraph DependenciesGraph {")
            print("node [shape = box]")
            recursiveWalk(rootpkg: rootpkg)
            print("}")
        } else {
            print("No external dependencies found")
        }
    }
}

private final class JSONDumper: DependenciesDumper {
    func dump(dependenciesOf rootpkg: ResolvedPackage) {
        func convert(_ package: ResolvedPackage) -> JSON {
            return .dictionary([
                    "name": .string(package.name),
                    "url": .string(package.manifest.url),
                    "version": .string(package.manifest.version?.description ?? "unspecified"),
                    "path": .string(package.path.asString),
                    "dependencies": .array(package.dependencies.map(convert)),
                ])
        }

        print(convert(rootpkg).toString(prettyPrint: true))
    }
}

enum ShowDependenciesMode: CustomStringConvertible {
    case text, dot, json

    init?(rawValue: String) {
        switch rawValue.lowercased() {
        case "text":
           self = .text
        case "dot":
           self = .dot
        case "json":
           self = .json
        default:
            return nil
        }
    }

    var description: String {
        switch self {
        case .text: return "text"
        case .dot: return "dot"
        case .json: return "json"
        }
    }
}
