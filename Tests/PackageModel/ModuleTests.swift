/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

@testable import PackageModel

class ModuleTests: XCTestCase {
    /// Check that module dependencies appear in build order.
    func testDependencyOrder() throws {
        let a = try Module(name: "a")
        let b = try Module(name: "b")
        let c = try Module(name: "c")
        a.dependencies.append(b)
        b.dependencies.append(c)
        XCTAssertEqual(a.recursiveDependencies, [c, b])
    }

    static var allTests = [
        ("testDependencyOrder", testDependencyOrder),
    ]
}
