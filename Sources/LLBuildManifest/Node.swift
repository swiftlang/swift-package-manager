//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics

package struct Node: Hashable, Codable {
    package enum Kind: String, Hashable, Codable {
        case virtual
        case file
        case directory
        case directoryStructure
    }

    struct Attributes: Hashable, Codable {
        var isMutated = false
        var isCommandTimestamp = false
    }

    /// The name used to identify the node.
    package var name: String

    /// The kind of node.
    package var kind: Kind

    let attributes: Attributes?

    private init(name: String, kind: Kind, attributes: Attributes? = nil) {
        self.name = name
        self.kind = kind
        self.attributes = attributes
    }
    
    /// Extracts `name` property if this node was constructed as `Node//virtual`.
    package var extractedVirtualNodeName: String {
        precondition(kind == .virtual)
        return String(self.name.dropFirst().dropLast())
    }

    package static func virtual(_ name: String, isCommandTimestamp: Bool = false) -> Node {
        precondition(name.first != "<" && name.last != ">", "<> will be inserted automatically")
        return Node(
            name: "<" + name + ">",
            kind: .virtual,
            attributes: isCommandTimestamp ? .init(isCommandTimestamp: isCommandTimestamp) : nil
        )
    }

    package static func file(_ name: AbsolutePath) -> Node {
        Node(name: name.pathString, kind: .file)
    }

    package static func file(_ name: AbsolutePath, isMutated: Bool) -> Node {
        Node(
            name: name.pathString,
            kind: .file,
            attributes: .init(isMutated: isMutated)
        )
    }

    package static func directory(_ name: AbsolutePath) -> Node {
        Node(name: name.pathString, kind: .directory)
    }

    package static func directoryStructure(_ name: AbsolutePath) -> Node {
        Node(name: name.pathString, kind: .directoryStructure)
    }
}

extension Array where Element == Node {
    package mutating func append(file path: AbsolutePath) {
        self.append(.file(path))
    }

    package mutating func append(directory path: AbsolutePath) {
        self.append(.directory(path))
    }

    package mutating func append(directoryStructure path: AbsolutePath) {
        self.append(.directoryStructure(path))
    }
}
