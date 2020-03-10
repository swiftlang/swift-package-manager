/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import PackageModel

public func dumpDependenciesOf(rootPackage: ResolvedPackage, mode: ShowDependenciesMode, on stream: OutputByteStream = stdoutStream) {
    let dumper: DependenciesDumper
    switch mode {
    case .text:
        dumper = PlainTextDumper()
    case .dot:
        dumper = DotDumper()
    case .json:
        dumper = JSONDumper()
    case .flatlist:
        dumper = FlatListDumper()
    }
    dumper.dump(dependenciesOf: rootPackage, on: stream)
    stream.flush()
}

private protocol DependenciesDumper {
    func dump(dependenciesOf: ResolvedPackage, on: OutputByteStream)
}

private final class PlainTextDumper: DependenciesDumper {
    func dump(dependenciesOf rootpkg: ResolvedPackage, on stream: OutputByteStream) {
        func recursiveWalk(packages: [ResolvedPackage], prefix: String = "") {
            var hanger = prefix + "├── "

            for (index, package) in packages.enumerated() {
                if index == packages.count - 1 {
                    hanger = prefix + "└── "
                }

                let pkgVersion = package.manifest.version?.description ?? "unspecified"

                stream <<< "\(hanger)\(package.name)<\(package.manifest.url)@\(pkgVersion)>\n"

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
            stream <<< (".\n")
            recursiveWalk(packages: rootpkg.dependencies)
        } else {
            stream <<< "No external dependencies found\n"
        }
    }
}

private final class FlatListDumper: DependenciesDumper {
    func dump(dependenciesOf rootpkg: ResolvedPackage, on stream: OutputByteStream) {
        func recursiveWalk(packages: [ResolvedPackage]) {
            for package in packages {
                stream <<< package.name <<< "\n"
                if !package.dependencies.isEmpty {
                    recursiveWalk(packages: package.dependencies)
                }
            }
        }
        if !rootpkg.dependencies.isEmpty {
            recursiveWalk(packages: rootpkg.dependencies)
        }
    }
}

private final class DotDumper: DependenciesDumper {
    func dump(dependenciesOf rootpkg: ResolvedPackage, on stream: OutputByteStream) {
        var nodesAlreadyPrinted: Set<String> = []
        func printNode(_ package: ResolvedPackage) {
            let url = package.manifest.url
            if nodesAlreadyPrinted.contains(url) { return }
            let pkgVersion = package.manifest.version?.description ?? "unspecified"
            stream <<< #""\#(url)" [label="\#(package.name)\n\#(url)\n\#(pkgVersion)"]"# <<< "\n"
            nodesAlreadyPrinted.insert(url)
        }
        
        struct DependencyURLs: Hashable {
            var root: String
            var dependency: String
        }
        var dependenciesAlreadyPrinted: Set<DependencyURLs> = []
        func recursiveWalk(rootpkg: ResolvedPackage) {
            printNode(rootpkg)
            for dependency in rootpkg.dependencies {
                let rootURL = rootpkg.manifest.url
                let dependencyURL = dependency.manifest.url
                let urlPair = DependencyURLs(root: rootURL, dependency: dependencyURL)
                if dependenciesAlreadyPrinted.contains(urlPair) { continue }
                
                printNode(dependency)
                stream <<< #""\#(rootURL)" -> "\#(dependencyURL)""# <<< "\n"
                dependenciesAlreadyPrinted.insert(urlPair)

                if !dependency.dependencies.isEmpty {
                    recursiveWalk(rootpkg: dependency)
                }
            }
        }

        if !rootpkg.dependencies.isEmpty {
            stream <<< "digraph DependenciesGraph {\n"
            stream <<< "node [shape = box]\n"
            recursiveWalk(rootpkg: rootpkg)
            stream <<< "}\n"
        } else {
            stream <<< "No external dependencies found\n"
        }
    }
}

private final class JSONDumper: DependenciesDumper {
    func dump(dependenciesOf rootpkg: ResolvedPackage, on stream: OutputByteStream) {
        func convert(_ package: ResolvedPackage) -> JSON {
            return .orderedDictionary([
                "name": .string(package.name),
                "url": .string(package.manifest.url),
                "version": .string(package.manifest.version?.description ?? "unspecified"),
                "path": .string(package.path.pathString),
                "dependencies": .array(package.dependencies.map(convert)),
            ])
        }

        stream <<< convert(rootpkg).toString(prettyPrint: true) <<< "\n"
    }
}

public enum ShowDependenciesMode: String, RawRepresentable, CustomStringConvertible {
    case text, dot, json, flatlist

    public init?(rawValue: String) {
        switch rawValue.lowercased() {
        case "text":
           self = .text
        case "dot":
           self = .dot
        case "json":
           self = .json
        case "flatlist":
            self = .flatlist
        default:
            return nil
        }
    }

    public var description: String {
        switch self {
        case .text: return "text"
        case .dot: return "dot"
        case .json: return "json"
        case .flatlist: return "flatlist"
        }
    }
}
