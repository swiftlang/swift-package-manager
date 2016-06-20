/*
 This source file is part of the Swift.org open source project
 
 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageModel
import struct PackageDescription.Version

func dumpDependenciesOf(rootPackage: Package, mode: ShowDependenciesMode) {
    let dumper: DependenciesDumper
    switch mode {
    case .text:
        dumper = PlainTextDumper()
    case .dot:
        dumper = DotDumper()
    case .json:
        dumper = JsonDumper()
    }
    dumper.dump(dependenciesOf: rootPackage)
}


fileprivate protocol DependenciesDumper {
    func dump(dependenciesOf: Package)
}


fileprivate final class PlainTextDumper: DependenciesDumper {
    func dump(dependenciesOf rootpkg: Package) {
        func recursiveWalk(packages: [Package], prefix: String = "") {
            var hanger = prefix + "├── "

            for (index, package) in packages.enumerated() {
                if index == packages.count - 1 {
                    hanger = prefix + "└── "
                }                

                let pkgVersion = package.version?.description ?? "unspecified"


                print("\(hanger)\(package.name)<\(package.url)@\(pkgVersion)>") 

                if !package.dependencies.isEmpty {
                    let replacement = (index == packages.count - 1) ?  "    " : "│   "
                    var childPrefix = hanger
                    childPrefix.replaceSubrange(childPrefix.index(childPrefix.endIndex, offsetBy: -4)..<childPrefix.endIndex, with: replacement)
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

fileprivate final class DotDumper: DependenciesDumper {
    func dump(dependenciesOf rootpkg: Package) {
        func recursiveWalk(rootpkg: Package) {
            printNode(rootpkg)
            for dependency in rootpkg.dependencies {
                printNode(dependency)
                print("\"\(rootpkg.url)\" -> \"\(dependency.url)\"")

                if !dependency.dependencies.isEmpty {
                    recursiveWalk(rootpkg: dependency)
                }
            }
        }

        func printNode(_ package: Package) {
            let pkgVersion = package.version?.description ?? "unspecified"
            print("\"\(package.url)\"[label=\"\(package.name)\\n\(package.url)\\n\(pkgVersion)\"]")
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

fileprivate final class JsonDumper: DependenciesDumper {
    func dump(dependenciesOf rootpkg: Package) {

        func recursiveWalk(rootpkg: Package, isLast: Bool = true) {
            print("{")
            print("\"name\":\"\(rootpkg.name)\",")
            print("\"url\":\"\(rootpkg.url)\",")
            let version = rootpkg.version?.description ?? "unspecified"
            print("\"version\":\"\(version)\",")
            print("\"path\":\"\(rootpkg.path)\",")
            print("\"dependencies\": [")

            for (index, dependency) in rootpkg.dependencies.enumerated() {
                recursiveWalk(rootpkg: dependency, isLast: (index + 1) == rootpkg.dependencies.endIndex)
            }

            print("]}" + (isLast ? "" : ","))
        }

        recursiveWalk(rootpkg: rootpkg)
    }
}

enum ShowDependenciesMode: CustomStringConvertible {
    case text, dot, json
    
    init(_ rawValue: String?) throws {
        guard let rawValue = rawValue else {
            self = .text
            return
        }
        
        switch rawValue.lowercased() {
        case "text":
           self = .text
        case "dot":
           self = .dot
        case "json":
           self = .json
        default:
            throw OptionParserError.invalidUsage("invalid show-dependencies mode: \(rawValue)")
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
