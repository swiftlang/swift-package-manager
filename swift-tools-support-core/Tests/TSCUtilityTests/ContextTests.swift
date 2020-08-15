// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors

import XCTest

import TSCUtility

struct SomeType {
    var name: String
}

class ContextTests: XCTestCase {
    func testBasics() {
        var ctx = Context()
        ctx.set(SomeType(name: "test"))
        XCTAssertEqual(ctx.get(SomeType.self).name, "test")

        ctx.set(SomeType(name: "optional"))
        XCTAssertEqual(ctx.getOptional(SomeType.self)?.name, "optional")
    }
}
