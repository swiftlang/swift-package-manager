/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import XCTest
@testable import dep

class PackageTests: XCTestCase {

    var allTests : [(String, () -> ())] {
        return []
    }

    func testInitializer() {
        do {
            // valid path, but no manifest so check throw is correct
            let foo1 = try Package(path: "foo-1.0.0")
            XCTAssertNil(foo1)
            // invalid path will return nil
            let foo2 = try Package(path: "foo")
            XCTAssertNil(foo2)

        } catch {
            XCTFail()
        }
    }
}
