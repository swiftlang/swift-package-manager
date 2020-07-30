/*
 This source file is part of the Swift.org open source project

 Copyright 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import XCTest
import TSCBasic
import TSCTestSupport

import TSCUtility

struct Key: Codable {
    var key: String
}

struct Value: Codable, Equatable {
    var str: String
    var int: Int
}

class PersistentCacheTests: XCTestCase {
    func testBasics() throws {
        mktmpdir { tmpPath in
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()
            let cacheFilePath = tmpPath.appending(component: "cache.db")
            let cache = try SQLiteBackedPersistentCache(cacheFilePath: cacheFilePath)

            let key1 = Key(key: "key1")
            let value1 = Value(str: "value1", int: 1)

            let key2 = Key(key: "key2")
            let value2 = Value(str: "value2", int: 2)

            XCTAssertNil(try cache.get(key: encoder.encode(key1)))
            XCTAssertNil(try cache.get(key: encoder.encode(key2)))

            try cache.put(key: encoder.encode(key1), value: encoder.encode(value1))
            try cache.put(key: encoder.encode(key2), value: encoder.encode(value2))

            let retVal1 = try cache.get(key: encoder.encode(key1)).map {
                try decoder.decode(Value.self, from: $0)
            }

            let retVal2 = try cache.get(key: encoder.encode(key2)).map {
                try decoder.decode(Value.self, from: $0)
            }

            XCTAssertEqual(retVal1, value1)
            XCTAssertEqual(retVal2, value2)

            try cache.put(key: encoder.encode(key1), value: encoder.encode(value2))
            let retVal3 = try cache.get(key: encoder.encode(key1)).map {
                try decoder.decode(Value.self, from: $0)
            }
            XCTAssertEqual(retVal3, value1)
        }
    }
}
