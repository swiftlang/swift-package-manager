/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// Allows encoding and decoding known polymorphic types.
public protocol PolymorphicCodableProtocol: Codable {
    static var implementations: [PolymorphicCodableProtocol.Type] { get }
}

@propertyWrapper
public struct PolymorphicCodable<T: PolymorphicCodableProtocol>: Codable {
    public let value: T

    public init(wrappedValue value: T) {
        self.value = value
    }

    public var wrappedValue: T {
        return value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(String(reflecting: type(of: value)))
        try container.encode(value)
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let typeCode = try container.decode(String.self)
        guard let klass = T.implementations.first(where: { String(reflecting: $0) == typeCode }) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unexpected Codable type code for concrete '\(type(of: T.self))': \(typeCode)")
        }

        self.value = try klass.init(from: container.superDecoder()) as! T
    }
}

@propertyWrapper
public struct PolymorphicCodableArray<T: PolymorphicCodableProtocol>: Codable {
    public let value: [PolymorphicCodable<T>]

    public init(wrappedValue value: [T]) {
        self.value = value.map{ PolymorphicCodable(wrappedValue: $0) }
    }

    public var wrappedValue: [T] {
        return value.map{ $0.value }
    }
}
