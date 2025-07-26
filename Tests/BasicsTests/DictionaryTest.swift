//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Testing

struct DictionaryTests {
    @Test
    func throwingUniqueKeysWithValues() throws {
        do {
            let keysWithValues = [("key1", "value1"), ("key2", "value2")]
            let dictionary = try Dictionary(throwingUniqueKeysWithValues: keysWithValues)
            #expect(dictionary["key1"] == "value1")
            #expect(dictionary["key2"] == "value2")
        }
        do {
            let keysWithValues = [("key1", "value"), ("key2", "value")]
            let dictionary = try Dictionary(throwingUniqueKeysWithValues: keysWithValues)
            #expect(dictionary["key1"] == "value")
            #expect(dictionary["key2"] == "value")
        }
        do {
            let keysWithValues = [("key", "value1"), ("key", "value2")]
            #expect(throws: StringError("duplicate key found: 'key'")) {
                try Dictionary(throwingUniqueKeysWithValues: keysWithValues)
            }
        }
    }
}
