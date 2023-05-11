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

import Basics
import XCTest

final class TripleTests: XCTestCase {
    func testDescription() throws {
        let triple = try Triple("x86_64-pc-linux-gnu")
        XCTAssertEqual("foo \(triple) bar", "foo x86_64-pc-linux-gnu bar")
    }
}
