/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import PackageDescription
import Utility

@testable import PackageLoading

private func parseTOML(_ data: String) -> TOMLItem {
    do {
        return try TOMLItem.parse(data)
    } catch let err {
        fatalError("unexpected error while parsing: \(err)")
    }
}

class SerializationTests: XCTestCase {
    func testBasics() {
        // Verify that we can round trip a basic package through TOML.
        let p1 = Package(name: "a", dependencies: [.Package(url: "https://example.com/example", majorVersion: 1)])
        XCTAssertEqual(p1, Package.fromTOML(parseTOML(p1.toTOML())))
    }

    func testExclude() {
        let exclude = ["Images", "A/B"]
        let p1 = Package(name: "a", exclude: exclude)
        let pFromTOML = Package.fromTOML(parseTOML(p1.toTOML()))
        XCTAssertEqual(pFromTOML.exclude, exclude)
    }

    func testTargetDependencyIsStringConvertible() {
      XCTAssertEqual(Target.Dependency.Target(name: "foo"), "foo")
    }

    static var allTests = [
        ("testBasics", testBasics),
        ("testExclude", testExclude),
        ("testTargetDependencyIsStringConvertible", testTargetDependencyIsStringConvertible)
    ]
}
