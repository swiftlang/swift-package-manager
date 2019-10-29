/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic

public struct Node: Hashable, Codable {
    public enum Kind: String, Hashable, Codable {
        case virtual
        case file
        case directory
        case directoryStructure
    }

    /// The name used to identify the node.
    public var name: String

    /// The kind of node.
    public var kind: Kind

    private init(name: String, kind: Kind) {
        self.name = name
        self.kind = kind
    }

    public static func virtual(_ name: String) -> Node {
        precondition(name.first != "<" && name.last != ">", "<> will be inserted automatically")
        return Node(name: "<" + name + ">", kind: .virtual)
    }

    public static func file(_ name: AbsolutePath) -> Node {
        Node(name: name.pathString, kind: .file)
    }

    public static func directory(_ name: AbsolutePath) -> Node {
        Node(name: name.pathString, kind: .directory)
    }

    public static func directoryStructure(_ name: AbsolutePath) -> Node {
        Node(name: name.pathString, kind: .directoryStructure)
    }
}

extension Array where Element == Node {
    public mutating func append(file path: AbsolutePath) {
        self.append(.file(path))
    }

    public mutating func append(directory path: AbsolutePath) {
        self.append(.directory(path))
    }

    public mutating func append(directoryStructure path: AbsolutePath) {
        self.append(.directoryStructure(path))
    }
}
