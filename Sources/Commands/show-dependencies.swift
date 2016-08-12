/*
 This source file is part of the Swift.org open source project
 
 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageModel

func dumpDependenciesOf(rootPackage: Package, mode: ShowDependenciesMode) {
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
    func dump(dependenciesOf: Package)
}


private final class PlainTextDumper: DependenciesDumper {
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

private final class DotDumper: DependenciesDumper {
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

private final class JSONDumper: DependenciesDumper {
    func dump(dependenciesOf rootpkg: Package) {
        func convert(_ package: Package) -> JSON {
            return .dictionary([
                    "name": .string(package.name),
                    "url": .string(package.url),
                    "version": .string(package.version?.description ?? "unspecified"),
                    "path": .string(package.path.asString),
                    "dependencies": .array(package.dependencies.map(convert))
                ])
        }

        print(convert(rootpkg).toString())
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
