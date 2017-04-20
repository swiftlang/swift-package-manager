/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic

class LazyCacheTests: XCTestCase {
    func testBasics() {
        class Foo {
            var numCalls = 0
            
            var bar: Int { return barCache.getValue(self) }
            var barCache = LazyCache<Foo, Int>(someExpensiveMethod)
            func someExpensiveMethod() -> Int {
                numCalls += 1
                return 42
            }
                
        }

        // FIXME: Make this a more interesting test once we have concurrency primitives.
        for _ in 0..<10 {
            let foo = Foo()
            XCTAssertEqual(foo.numCalls, 0)
            for _ in 0..<10 {
                XCTAssertEqual(foo.bar, 42)
                XCTAssertEqual(foo.numCalls, 1)
            }
        }
    }

    static var allTests = [
        ("testBasics", testBasics),
    ]
}
