//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@testable import Basics
import XCTest

final class DictionaryTests: XCTestCase {
    func testThrowingUniqueKeysWithValues() throws {
        do {
            let keysWithValues = [("key1", "value1"), ("key2", "value2")]
            let dictionary = try Dictionary(throwingUniqueKeysWithValues: keysWithValues)
            XCTAssertEqual(dictionary["key1"], "value1")
            XCTAssertEqual(dictionary["key2"], "value2")
        }
        do {
            let keysWithValues = [("key1", "value"), ("key2", "value")]
            let dictionary = try Dictionary(throwingUniqueKeysWithValues: keysWithValues)
            XCTAssertEqual(dictionary["key1"], "value")
            XCTAssertEqual(dictionary["key2"], "value")
        }
        do {
            let keysWithValues = [("key", "value1"), ("key", "value2")]
            XCTAssertThrowsError(try Dictionary(throwingUniqueKeysWithValues: keysWithValues)) { error in
                XCTAssertEqual(error as? StringError, StringError("duplicate key found: 'key'"))
            }
        }
    }
}
