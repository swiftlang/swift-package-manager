/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic

final class Person {
    let name: String
    init(_ name: String) {
        self.name = name
    }
}

extension Person: ObjectIdentifierProtocol {}

class ObjectIdentifierProtocolTests: XCTestCase {

    func testBasics() {
        let foo = Person("Foo")
        let foo2 = Person("Foo2")
        let foo3 = foo
        let bar = Person("Bar")
        let bar2 = bar

        XCTAssertNotEqual(foo, foo2)
        XCTAssertNotEqual(foo2, foo3)
        XCTAssertEqual(foo, foo3)
        
        XCTAssertNotEqual(foo, bar)
        XCTAssertNotEqual(foo, bar2)
        XCTAssertEqual(bar, bar2)

        var dict = [Person: String]()
        dict[foo] = foo.name
        dict[bar] = bar.name

        XCTAssertEqual(dict[foo], "Foo")
        XCTAssertEqual(dict[foo2], nil)
        XCTAssertEqual(dict[foo3], "Foo")

        XCTAssertEqual(dict[bar], "Bar")
        XCTAssertEqual(dict[bar2], "Bar")
    }

    static var allTests = [
        ("testBasics", testBasics),
    ]
}
