/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import TSCBasic

class CollectionAlgorithmsTests: XCTestCase {
    func testFindDuplicates() {
        XCTAssertEqual(Set([1, 2, 3, 2, 1].spm_findDuplicates()), [1, 2])
        XCTAssertEqual(Set([1, 2, 3, 2, 1, 2].spm_findDuplicates()), [1, 2])
        XCTAssertEqual(["foo", "bar"].spm_findDuplicates(), [])
        XCTAssertEqual(["foo", "Foo"].spm_findDuplicates(), [])
    }
}
