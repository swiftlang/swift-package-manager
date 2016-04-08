/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Update
import struct PackageDescription.Version
import XCTest

class UpdateTestCase: XCTestCase {

    func testEmptyGraph() {

        struct Package: Update.Package {
            let path = ""
            let version = Version(0,0,0)
            let url = ""

            func commit(newVersion: Version) {}
            func fetch() {}
        }

        let b: [Package] = update(graph: [])
        XCTAssertEqual(b.count, 0)
    }
}
