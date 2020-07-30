// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors

import XCTest

import TSCUtility

class TracingTests: XCTestCase {
    func testBasics() {
        let event1 = TracingEvent(cat: "cat", name: "name", id: "1", ph: .asyncBegin)
        var collection = TracingCollection()
        collection.events.append(event1)
        let event2 = TracingEvent(cat: "cat", name: "name", id: "1", ph: .asyncEnd)
        collection.events.append(event2)
        XCTAssertEqual(collection.events.count, 2)
        var ctx = Context()
        ctx.tracing = collection
        XCTAssertEqual(ctx.tracing?.events.count, 2)
        let collection2 = TracingCollection()
        collection2.events.append(event2)
        collection.append(collection2)
        XCTAssertEqual(collection.events.count, 3)
        XCTAssertEqual(ctx.tracing?.events.count, 3)
    }
}
