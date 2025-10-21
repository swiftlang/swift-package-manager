//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Foundation

@testable import Basics
import Testing

struct EnvironmentKeyTests {
    @Test
    func comparable() {
        let key0 = EnvironmentKey("Test")
        let key1 = EnvironmentKey("Test1")
        #expect(key0 < key1)

        let key2 = EnvironmentKey("test")
        #expect(key0 < key2)
    }

    @Test
    func customStringConvertible() {
        let key = EnvironmentKey("Test")
        #expect(key.description == "Test")
    }

    @Test
    func encodable() throws {
        let key = EnvironmentKey("Test")
        let data = try JSONEncoder().encode(key)
        let string = String(data: data, encoding: .utf8)
        #expect(string == #""Test""#)
    }

    @Test
    func equatable() {
        let key0 = EnvironmentKey("Test")
        let key1 = EnvironmentKey("Test")
        #expect(key0 == key1)

        let key2 = EnvironmentKey("Test2")
        #expect(key0 != key2)

        #if os(Windows)
        // Test case insensitivity on windows
        let key3 = EnvironmentKey("teSt")
            #expect(key0 == key3)
        #endif
    }

    @Test
    func expressibleByStringLiteral() {
        let key0 = EnvironmentKey("Test")
        #expect(key0 == "Test")
    }

    @Test
    func decodable() throws {
        let jsonString = #""Test""#
        let data = jsonString.data(using: .utf8)!
        let key = try JSONDecoder().decode(EnvironmentKey.self, from: data)
        #expect(key.rawValue == "Test")
    }

    @Test
    func hashable() {
        var set = Set<EnvironmentKey>()
        let key0 = EnvironmentKey("Test")
        #expect(set.insert(key0).inserted)

        let key1 = EnvironmentKey("Test")
        #expect(set.contains(key1))
        #expect(!set.insert(key1).inserted)

        let key2 = EnvironmentKey("Test2")
        #expect(!set.contains(key2))
        #expect(set.insert(key2).inserted)

        #if os(Windows)
        // Test case insensitivity on windows
        let key3 = EnvironmentKey("teSt")
            #expect(set.contains(key3))
            #expect(!set.insert(key3).inserted)
        #endif

        #expect(set == ["Test", "Test2"])
    }

    @Test
    func rawRepresentable() {
        let key = EnvironmentKey(rawValue: "Test")
        #expect(key?.rawValue == "Test")
    }
}
