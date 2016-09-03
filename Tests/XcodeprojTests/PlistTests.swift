/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
@testable import Xcodeproj

class PlistTests: XCTestCase {
    func testBasics() {
        XCTAssertEqual("\"hello \\\" world\"", Plist.string("hello \" world").serialize())
        XCTAssertEqual("(\"hello world\", \"cool\")", Plist.array([.string("hello world"), .string("cool")]).serialize())
        XCTAssertEqual("{ polo = (\"hello \\\" world\", \"cool\") ;  user = \"cool\" ; };", Plist.dictionary(["user": .string("cool"), "polo": Plist.array([.string("hello \" world"), .string("cool")])]).serialize())
    }

    static var allTests = [
        ("testBasics", testBasics),
    ]
}
