/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import TSCBasic

class DictionaryExtensionTests: XCTestCase {

    func testBasics() {
        XCTAssertEqual(["foo": "1", "bar": "2", "baz": "f"].spm_flatMapValues({ Int($0) }), ["foo": 1, "bar": 2])
    }

    func testCreateDictionary() {
        XCTAssertEqual([("foo", 1), ("bar", 2)].spm_createDictionary({ $0 }), ["foo": 1, "bar": 2])
        XCTAssertEqual(["foo", "bar"].spm_createDictionary({ ($0[$0.startIndex], $0) }), ["f": "foo", "b": "bar"])
    }
}
