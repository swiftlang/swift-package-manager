/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import Xcodeproj

class PropertyListTests: XCTestCase {
    func testBasics() {
        XCTAssertEqual("\"hello \\\" world\"", PropertyList.string("hello \" world").serialize())
        XCTAssertEqual("(\n   \"hello world\",\n   \"cool\"\n)", PropertyList.array([.string("hello world"), .string("cool")]).serialize())
        XCTAssertEqual("{\n   polo = (\n      \"hello \\\" world\",\n      \"cool\"\n   );\n   user = \"cool\";\n}", PropertyList.dictionary(["user": .string("cool"), "polo": PropertyList.array([.string("hello \" world"), .string("cool")])]).serialize())
    }
}
