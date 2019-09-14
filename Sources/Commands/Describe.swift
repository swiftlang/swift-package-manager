/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import PackageModel

enum DescribeMode: String {
    /// JSON format.
    case json

    /// Human readable format.
    case text
}

func describe(_ package: Package, in mode: DescribeMode, on stream: OutputByteStream) {
    switch mode {
    case .json:
        stream <<< package.toJSON().toString(prettyPrint: true) <<< "\n"
    case .text:
        package.describe(on: stream)
    }
    stream.flush()
}

extension Package: JSONSerializable {

    func describe(on stream: OutputByteStream) {
        stream <<< """
            Name: \(name)
            Path: \(path)
            Modules:\n
            """
        for target in targets.sorted(by: { $0.name > $1.name }) {
            target.describe(on: stream, indent: 4)
            stream <<< "\n"
        }
    }

    public func toJSON() -> JSON {
        return .init([
            "name": name,
            "path": path,
            "targets": targets.sorted(by: { $0.name > $1.name }),
        ])
    }
}

extension Target: JSONSerializable {

    func describe(on stream: OutputByteStream, indent: Int = 0) {
        stream <<< Format.asRepeating(string: " ", count: indent)
            <<< "Name: " <<< name <<< "\n"
        stream <<< Format.asRepeating(string: " ", count: indent)
            <<< "C99name: " <<< c99name <<< "\n"
        stream <<< Format.asRepeating(string: " ", count: indent)
            <<< "Type: " <<< type.rawValue <<< "\n"
        stream <<< Format.asRepeating(string: " ", count: indent)
            <<< "Module type: " <<< String(describing: Swift.type(of: self)) <<< "\n"
        stream <<< Format.asRepeating(string: " ", count: indent)
            <<< "Path: " <<< sources.root.pathString <<< "\n"
        stream <<< Format.asRepeating(string: " ", count: indent)
            <<< "Sources: " <<< sources.relativePaths.map({ $0.pathString }).joined(separator: ", ") <<< "\n"
    }

    public func toJSON() -> JSON {
        return .init([
            "name": name,
            "c99name": c99name,
            "type": type,
            "module_type": String(describing: Swift.type(of: self)),
            "path": sources.root,
            "sources": sources
        ])
    }
}

extension Sources: JSONSerializable {
    public func toJSON() -> JSON {
        return .array(relativePaths.map({ .string($0.pathString) }))
    }
}

extension Target.Kind: JSONSerializable {
    public func toJSON() -> JSON {
        return .string(rawValue)
    }
}
