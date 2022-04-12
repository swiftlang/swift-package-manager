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

import PackagePlugin
import XCTest

class PathAPITests: XCTestCase {

    func testBasics() throws {
        let path = Path("/tmp/file.foo")
        XCTAssertEqual(path.lastComponent, "file.foo")
        XCTAssertEqual(path.stem, "file")
        XCTAssertEqual(path.extension, "foo")
        XCTAssertEqual(path.removingLastComponent(), Path("/tmp"))
    }

    func testEdgeCases() throws {
        let path = Path("/tmp/file.foo")
        XCTAssertEqual(path.removingLastComponent().removingLastComponent().removingLastComponent(), Path("/"))
    }
}
