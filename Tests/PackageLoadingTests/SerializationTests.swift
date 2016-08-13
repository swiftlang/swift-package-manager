/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
@testable import PackageDescription
import Utility

@testable import PackageLoading

private func parseJSON(_ data: String) -> Basic.JSON {
    do {
        return try JSON(string: data)
    } catch let err {
        fatalError("unexpected error while parsing: \(err)")
    }
}

class SerializationTests: XCTestCase {
    func testBasics() {
        // Verify that we can round trip a basic package through JSON.
        let p1 = Package(name: "a", dependencies: [.Package(url: "https://example.com/example", majorVersion: 1)])
        XCTAssertEqual(p1, Package.fromJSON(parseJSON(manifestToJSON(p1))))
    }

    func testExclude() {
        let exclude = ["Images", "A/B"]
        let p1 = Package(name: "a", exclude: exclude)
        let pFromJSON = Package.fromJSON(parseJSON(manifestToJSON(p1)))
        XCTAssertEqual(pFromJSON.exclude, exclude)
    }

    func testTargetDependencyIsStringConvertible() {
      XCTAssertEqual(Target.Dependency.Target(name: "foo"), "foo")
    }

    func testInvalidVersionString() {
        let p = Package(name: "a", dependencies: [.Package(url: "https://example.com/example", "1.0,0")])
        XCTAssertEqual(parseErrors(parseJSON(manifestToJSON(p))), ["Invalid version string: 1.0,0"])
    }

    static var allTests = [
        ("testBasics", testBasics),
        ("testExclude", testExclude),
        ("testTargetDependencyIsStringConvertible", testTargetDependencyIsStringConvertible),
        ("testInvalidVersionString", testInvalidVersionString),
    ]
}
