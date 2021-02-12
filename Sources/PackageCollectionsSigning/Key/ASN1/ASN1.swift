/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftCrypto open source project
//
// Copyright (c) 2019-2020 Apple Inc. and the SwiftCrypto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.md for the list of SwiftCrypto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation

// Source code in the ASN1 subdirectory is taken from SwiftCrypto and provides an even more
// limited set of functionalities than what's in SwiftCrypto. The sole purpose is to parse
// keys in PEM format for older macOS versions, since `init(pemRepresentation:)` is not
// available until macOS 11. For complete source files, see https://github.com/apple/swift-crypto.

// Source: https://github.com/apple/swift-crypto/blob/main/Sources/Crypto/ASN1/ASN1.swift

internal enum ASN1 {}

// MARK: - Parser Node

extension ASN1 {
    /// An `ASN1ParserNode` is a representation of a parsed ASN.1 TLV section. An `ASN1ParserNode` may be primitive, or may be composed of other `ASN1ParserNode`s.
    /// In our representation, we keep track of this by storing a node "depth", which allows rapid forward and backward scans to hop over sections
    /// we're uninterested in.
    ///
    /// This type is not exposed to users of the API: it is only used internally for implementation of the user-level API.
    fileprivate struct ASN1ParserNode {
        /// The identifier.
        var identifier: ASN1Identifier

        /// The depth of this node.
        var depth: Int

        /// The data bytes for this node, if it is primitive.
        var dataBytes: ArraySlice<UInt8>?
    }
}

extension ASN1.ASN1ParserNode: Hashable {}

// MARK: - Sequence

extension ASN1 {
    /// Parse the node as an ASN.1 sequence.
    internal static func sequence<T>(_ node: ASN1Node, _ builder: (inout ASN1.ASN1NodeCollection.Iterator) throws -> T) throws -> T {
        guard node.identifier == .sequence, case .constructed(let nodes) = node.content else {
            throw ASN1Error.unexpectedFieldType
        }

        var iterator = nodes.makeIterator()

        let result = try builder(&iterator)

        guard iterator.next() == nil else {
            throw ASN1Error.invalidASN1Object
        }

        return result
    }
}

// MARK: - Optional explicitly tagged

extension ASN1 {
    /// Parses an optional explicitly tagged element. Throws on a tag mismatch, returns nil if the element simply isn't there.
    ///
    /// Expects to be used with the `ASN1.sequence` helper function.
    internal static func optionalExplicitlyTagged<T>(_ nodes: inout ASN1.ASN1NodeCollection.Iterator, tagNumber: Int, tagClass: ASN1.ASN1Identifier.TagClass, _ builder: (ASN1Node) throws -> T) throws -> T? {
        var localNodesCopy = nodes
        guard let node = localNodesCopy.next() else {
            // Node not present, return nil.
            return nil
        }

        let expectedNodeID = ASN1.ASN1Identifier(explicitTagWithNumber: tagNumber, tagClass: tagClass)
        assert(expectedNodeID.constructed)
        guard node.identifier == expectedNodeID else {
            // Node is a mismatch, with the wrong tag. Our optional isn't present.
            return nil
        }

        // We have the right optional, so let's consume it.
        nodes = localNodesCopy

        // We expect a single child.
        guard case .constructed(let nodes) = node.content else {
            // This error is an internal parser error: the tag above is always constructed.
            preconditionFailure("Explicit tags are always constructed")
        }

        var nodeIterator = nodes.makeIterator()
        guard let child = nodeIterator.next(), nodeIterator.next() == nil else {
            throw ASN1Error.invalidASN1Object
        }

        return try builder(child)
    }
}

// MARK: - Parsing

extension ASN1 {
    /// A parsed representation of ASN.1.
    fileprivate struct ASN1ParseResult {
        private static let maximumNodeDepth = 10

        var nodes: ArraySlice<ASN1ParserNode>

        private init(_ nodes: ArraySlice<ASN1ParserNode>) {
            self.nodes = nodes
        }

        fileprivate static func parse(_ data: ArraySlice<UInt8>) throws -> ASN1ParseResult {
            var data = data
            var nodes = [ASN1ParserNode]()
            nodes.reserveCapacity(16)

            try self.parseNode(from: &data, depth: 1, into: &nodes)
            guard data.count == 0 else {
                throw ASN1Error.invalidASN1Object
            }
            return ASN1ParseResult(nodes[...])
        }

        /// Parses a single ASN.1 node from the data and appends it to the buffer. This may recursively
        /// call itself when there are child nodes for constructed nodes.
        private static func parseNode(from data: inout ArraySlice<UInt8>, depth: Int, into nodes: inout [ASN1ParserNode]) throws {
            guard depth <= ASN1.ASN1ParseResult.maximumNodeDepth else {
                // We defend ourselves against stack overflow by refusing to allocate more than 10 stack frames to
                // the parsing.
                throw ASN1Error.invalidASN1Object
            }

            guard let rawIdentifier = data.popFirst() else {
                throw ASN1Error.truncatedASN1Field
            }

            let identifier = try ASN1Identifier(rawIdentifier: rawIdentifier)
            guard let wideLength = try data.readASN1Length() else {
                throw ASN1Error.truncatedASN1Field
            }

            // UInt is sometimes too large for us!
            guard let length = Int(exactly: wideLength) else {
                throw ASN1Error.invalidASN1Object
            }

            var subData = data.prefix(length)
            data = data.dropFirst(length)

            guard subData.count == length else {
                throw ASN1Error.truncatedASN1Field
            }

            if identifier.constructed {
                nodes.append(ASN1ParserNode(identifier: identifier, depth: depth, dataBytes: nil))
                while subData.count > 0 {
                    try self.parseNode(from: &subData, depth: depth + 1, into: &nodes)
                }
            } else {
                nodes.append(ASN1ParserNode(identifier: identifier, depth: depth, dataBytes: subData))
            }
        }
    }
}

extension ASN1.ASN1ParseResult: Hashable {}

extension ASN1 {
    static func parse(_ data: [UInt8]) throws -> ASN1Node {
        return try self.parse(data[...])
    }

    static func parse(_ data: ArraySlice<UInt8>) throws -> ASN1Node {
        var result = try ASN1ParseResult.parse(data)

        // There will always be at least one node if the above didn't throw, so we can safely just removeFirst here.
        let firstNode = result.nodes.removeFirst()

        let rootNode: ASN1Node
        if firstNode.identifier.constructed {
            // We need to feed it the next set of nodes.
            let nodeCollection = result.nodes.prefix { $0.depth > firstNode.depth }
            result.nodes = result.nodes.dropFirst(nodeCollection.count)
            rootNode = ASN1.ASN1Node(identifier: firstNode.identifier, content: .constructed(.init(nodes: nodeCollection, depth: firstNode.depth)))
        } else {
            rootNode = ASN1.ASN1Node(identifier: firstNode.identifier, content: .primitive(firstNode.dataBytes!))
        }

        precondition(result.nodes.count == 0, "ASN1ParseResult unexpectedly allowed multiple root nodes")

        return rootNode
    }
}

// MARK: - ASN1NodeCollection

extension ASN1 {
    /// Represents a collection of ASN.1 nodes contained in a constructed ASN.1 node.
    ///
    /// Constructed ASN.1 nodes are made up of multiple child nodes. This object represents the collection of those child nodes.
    /// It allows us to lazily construct the child nodes, potentially skipping over them when we don't care about them.
    internal struct ASN1NodeCollection {
        private var nodes: ArraySlice<ASN1ParserNode>

        private var depth: Int

        fileprivate init(nodes: ArraySlice<ASN1ParserNode>, depth: Int) {
            self.nodes = nodes
            self.depth = depth

            precondition(self.nodes.allSatisfy { $0.depth > depth })
            if let firstDepth = self.nodes.first?.depth {
                precondition(firstDepth == depth + 1)
            }
        }
    }
}

extension ASN1.ASN1NodeCollection: Sequence {
    struct Iterator: IteratorProtocol {
        private var nodes: ArraySlice<ASN1.ASN1ParserNode>
        private var depth: Int

        fileprivate init(nodes: ArraySlice<ASN1.ASN1ParserNode>, depth: Int) {
            self.nodes = nodes
            self.depth = depth
        }

        mutating func next() -> ASN1.ASN1Node? {
            guard let nextNode = self.nodes.popFirst() else {
                return nil
            }

            assert(nextNode.depth == self.depth + 1)
            if nextNode.identifier.constructed {
                // We need to feed it the next set of nodes.
                let nodeCollection = self.nodes.prefix { $0.depth > nextNode.depth }
                self.nodes = self.nodes.dropFirst(nodeCollection.count)
                return ASN1.ASN1Node(identifier: nextNode.identifier, content: .constructed(.init(nodes: nodeCollection, depth: nextNode.depth)))
            } else {
                // There must be data bytes here, even if they're empty.
                return ASN1.ASN1Node(identifier: nextNode.identifier, content: .primitive(nextNode.dataBytes!))
            }
        }
    }

    func makeIterator() -> Iterator {
        return Iterator(nodes: self.nodes, depth: self.depth)
    }
}

// MARK: - ASN1Node

extension ASN1 {
    /// An `ASN1Node` is a single entry in the ASN.1 representation of a data structure.
    ///
    /// Conceptually, an ASN.1 data structure is rooted in a single node, which may itself contain zero or more
    /// other nodes. ASN.1 nodes are either "constructed", meaning they contain other nodes, or "primitive", meaning they
    /// store a base data type of some kind.
    ///
    /// In this way, ASN.1 objects tend to form a "tree", where each object is represented by a single top-level constructed
    /// node that contains other objects and primitives, eventually reaching the bottom which is made up of primitive objects.
    internal struct ASN1Node {
        internal var identifier: ASN1Identifier

        internal var content: Content
    }
}

// MARK: - ASN1Node.Content

extension ASN1.ASN1Node {
    /// The content of a single ASN1Node.
    enum Content {
        case constructed(ASN1.ASN1NodeCollection)
        case primitive(ArraySlice<UInt8>)
    }
}

// MARK: - Helpers

internal protocol ASN1Parseable {
    init(asn1Encoded: ASN1.ASN1Node) throws
}

extension ASN1Parseable {
    internal init(asn1Encoded sequenceNodeIterator: inout ASN1.ASN1NodeCollection.Iterator) throws {
        guard let node = sequenceNodeIterator.next() else {
            throw ASN1Error.invalidASN1Object
        }

        self = try .init(asn1Encoded: node)
    }

    internal init(asn1Encoded: [UInt8]) throws {
        self = try .init(asn1Encoded: ASN1.parse(asn1Encoded))
    }
}

extension ArraySlice where Element == UInt8 {
    fileprivate mutating func readASN1Length() throws -> UInt? {
        guard let firstByte = self.popFirst() else {
            return nil
        }

        switch firstByte {
        case 0x80:
            // Indefinite form. Unsupported.
            throw ASN1Error.unsupportedFieldLength
        case let val where val & 0x80 == 0x80:
            // Top bit is set, this is the long form. The remaining 7 bits of this octet
            // determine how long the length field is.
            let fieldLength = Int(val & 0x7F)
            guard self.count >= fieldLength else {
                return nil
            }

            // We need to read the length bytes
            let lengthBytes = self.prefix(fieldLength)
            self = self.dropFirst(fieldLength)
            let length = try UInt(bigEndianBytes: lengthBytes)

            // DER requires that we enforce that the length field was encoded in the minimum number of octets necessary.
            let requiredBits = UInt.bitWidth - length.leadingZeroBitCount
            switch requiredBits {
            case 0 ... 7:
                // For 0 to 7 bits, the long form is unnacceptable and we require the short.
                throw ASN1Error.unsupportedFieldLength
            case 8...:
                // For 8 or more bits, fieldLength should be the minimum required.
                let requiredBytes = (requiredBits + 7) / 8
                if fieldLength > requiredBytes {
                    throw ASN1Error.unsupportedFieldLength
                }
            default:
                // This is not reachable, but we'll error anyway.
                throw ASN1Error.unsupportedFieldLength
            }

            return length
        case let val:
            // Short form, the length is only one 7-bit integer.
            return UInt(val)
        }
    }
}

extension FixedWidthInteger {
    internal init<Bytes: Collection>(bigEndianBytes bytes: Bytes) throws where Bytes.Element == UInt8 {
        guard bytes.count <= (Self.bitWidth / 8) else {
            throw ASN1Error.invalidASN1Object
        }

        self = 0
        let shiftSizes = stride(from: 0, to: bytes.count * 8, by: 8).reversed()

        var index = bytes.startIndex
        for shift in shiftSizes {
            self |= Self(truncatingIfNeeded: bytes[index]) << shift
            bytes.formIndex(after: &index)
        }
    }
}

extension FixedWidthInteger {
    // Bytes needed to store a given integer.
    internal var neededBytes: Int {
        let neededBits = self.bitWidth - self.leadingZeroBitCount
        return (neededBits + 7) / 8
    }
}
