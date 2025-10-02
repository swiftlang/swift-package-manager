//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

package import struct SystemPackage.FilePath

package protocol Query: Sendable {
    associatedtype Key: CacheKey
    var cacheKey: Key { get }
    func run(engine: QueryEngine) async throws -> FilePath
}

package protocol CachingQuery: Query, CacheKey where Self.Key == Self {}
extension CachingQuery {
    package var cacheKey: Key { self }
}

// SwiftPM has to be built with Swift 5.8 on CI and also needs to support CMake for bootstrapping on Windows.
// This means we can't implement persistable hashing with macros (unavailable in Swift 5.8 and additional effort to
// set up with CMake when Swift 5.9 is available for all CI jobs) and have to stick to `Encodable` for now.
final class HashEncoder<Hash: HashFunction>: Encoder {
    enum Error: Swift.Error {
        case noCacheKeyConformance(Encodable.Type)
    }

    var codingPath: [any CodingKey]

    var userInfo: [CodingUserInfoKey: Any]

    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key: CodingKey {
        .init(KeyedContainer(encoder: self))
    }

    func unkeyedContainer() -> any UnkeyedEncodingContainer {
        self
    }

    func singleValueContainer() -> any SingleValueEncodingContainer {
        self
    }

    init() {
        self.hashFunction = Hash()
        self.codingPath = []
        self.userInfo = [:]
    }

    fileprivate var hashFunction = Hash()

    func finalize() -> Hash.Digest {
        self.hashFunction.finalize()
    }
}

extension HashEncoder: SingleValueEncodingContainer {
    func encodeNil() throws {
        // FIXME: this doesn't encode the name of the underlying optional type,
        // but `Encoder` protocol is limited and can't provide this for us.
        var str = "nil"
        str.withUTF8 {
            self.hashFunction.update(data: $0)
        }
    }

    func encode(_ value: Bool) throws {
        value.hash(with: &self.hashFunction)
    }

    func encode(_ value: String) throws {
        value.hash(with: &self.hashFunction)
    }

    func encode(_ value: Double) throws {
        value.hash(with: &self.hashFunction)
    }

    func encode(_ value: Float) throws {
        value.hash(with: &self.hashFunction)
    }

    func encode(_ value: Int) throws {
        value.hash(with: &self.hashFunction)
    }

    func encode(_ value: Int8) throws {
        value.hash(with: &self.hashFunction)
    }

    func encode(_ value: Int16) throws {
        value.hash(with: &self.hashFunction)
    }

    func encode(_ value: Int32) throws {
        value.hash(with: &self.hashFunction)
    }

    func encode(_ value: Int64) throws {
        value.hash(with: &self.hashFunction)
    }

    func encode(_ value: UInt) throws {
        value.hash(with: &self.hashFunction)
    }

    func encode(_ value: UInt8) throws {
        value.hash(with: &self.hashFunction)
    }

    func encode(_ value: UInt16) throws {
        value.hash(with: &self.hashFunction)
    }

    func encode(_ value: UInt32) throws {
        value.hash(with: &self.hashFunction)
    }

    func encode(_ value: UInt64) throws {
        value.hash(with: &self.hashFunction)
    }

    func encode<T>(_ value: T) throws where T: Encodable {
        if let leaf = value as? LeafCacheKey {
            leaf.hash(with: &self.hashFunction)
            return
        }

        guard value is CacheKey else {
            throw Error.noCacheKeyConformance(T.self)
        }

        try String(describing: T.self).encode(to: self)
        try value.encode(to: self)
    }
}

extension HashEncoder: UnkeyedEncodingContainer {
    var count: Int {
        0
    }

    func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey>
    where NestedKey: CodingKey {
        KeyedEncodingContainer(KeyedContainer(encoder: self))
    }

    func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
        self
    }

    func superEncoder() -> any Encoder {
        fatalError()
    }
}

extension HashEncoder {
    struct KeyedContainer<K: CodingKey>: KeyedEncodingContainerProtocol {
        var encoder: HashEncoder
        var codingPath: [any CodingKey] { self.encoder.codingPath }

        mutating func encodeNil(forKey key: K) throws {
            // FIXME: this doesn't encode the name of the underlying optional type,
            // but `Encoder` protocol is limited and can't provide this for us.
            var str = "nil"
            str.withUTF8 {
                self.encoder.hashFunction.update(data: $0)
            }
        }

        mutating func encode(_ value: Bool, forKey key: K) throws {
            key.stringValue.hash(with: &self.encoder.hashFunction)
            value.hash(with: &self.encoder.hashFunction)
        }

        mutating func encode(_ value: String, forKey key: K) throws {
            key.stringValue.hash(with: &self.encoder.hashFunction)
            value.hash(with: &self.encoder.hashFunction)
        }

        mutating func encode(_ value: Double, forKey key: K) throws {
            key.stringValue.hash(with: &self.encoder.hashFunction)
            value.hash(with: &self.encoder.hashFunction)
        }

        mutating func encode(_ value: Float, forKey key: K) throws {
            key.stringValue.hash(with: &self.encoder.hashFunction)
            value.hash(with: &self.encoder.hashFunction)
        }

        mutating func encode(_ value: Int, forKey key: K) throws {
            key.stringValue.hash(with: &self.encoder.hashFunction)
            value.hash(with: &self.encoder.hashFunction)
        }

        mutating func encode(_ value: Int8, forKey key: K) throws {
            key.stringValue.hash(with: &self.encoder.hashFunction)
            value.hash(with: &self.encoder.hashFunction)
        }

        mutating func encode(_ value: Int16, forKey key: K) throws {
            key.stringValue.hash(with: &self.encoder.hashFunction)
            value.hash(with: &self.encoder.hashFunction)
        }

        mutating func encode(_ value: Int32, forKey key: K) throws {
            key.stringValue.hash(with: &self.encoder.hashFunction)
            value.hash(with: &self.encoder.hashFunction)
        }

        mutating func encode(_ value: Int64, forKey key: K) throws {
            key.stringValue.hash(with: &self.encoder.hashFunction)
            value.hash(with: &self.encoder.hashFunction)
        }

        mutating func encode(_ value: UInt, forKey key: K) throws {
            key.stringValue.hash(with: &self.encoder.hashFunction)
            value.hash(with: &self.encoder.hashFunction)
        }

        mutating func encode(_ value: UInt8, forKey key: K) throws {
            key.stringValue.hash(with: &self.encoder.hashFunction)
            value.hash(with: &self.encoder.hashFunction)
        }

        mutating func encode(_ value: UInt16, forKey key: K) throws {
            key.stringValue.hash(with: &self.encoder.hashFunction)
            value.hash(with: &self.encoder.hashFunction)
        }

        mutating func encode(_ value: UInt32, forKey key: K) throws {
            key.stringValue.hash(with: &self.encoder.hashFunction)
            value.hash(with: &self.encoder.hashFunction)
        }

        mutating func encode(_ value: UInt64, forKey key: K) throws {
            key.stringValue.hash(with: &self.encoder.hashFunction)
            value.hash(with: &self.encoder.hashFunction)
        }

        mutating func encode<T>(_ value: T, forKey key: K) throws where T: Encodable {
            if let leaf = value as? LeafCacheKey {
                leaf.hash(with: &self.encoder.hashFunction)
                return
            }
            guard value is CacheKey else {
                throw Error.noCacheKeyConformance(T.self)
            }

            try String(reflecting: T.self).encode(to: self.encoder)
            key.stringValue.hash(with: &self.encoder.hashFunction)
            try value.encode(to: self.encoder)
        }

        mutating func nestedContainer<NestedKey>(
            keyedBy keyType: NestedKey.Type,
            forKey key: K
        ) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
            key.stringValue.hash(with: &self.encoder.hashFunction)
            return self.encoder.nestedContainer(keyedBy: keyType)
        }

        mutating func nestedUnkeyedContainer(forKey key: K) -> any UnkeyedEncodingContainer {
            key.stringValue.hash(with: &self.encoder.hashFunction)
            return self.encoder
        }

        mutating func superEncoder() -> any Encoder {
            fatalError()
        }

        mutating func superEncoder(forKey key: K) -> any Encoder {
            fatalError()
        }

        typealias Key = K
    }
}
