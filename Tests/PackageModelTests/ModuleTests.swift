/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import Basic

@testable import PackageModel

private extension Module {
    convenience init(name: String, dependencies: [Module] = []) throws {
        try self.init(name: name, type: .library, sources: Sources(paths: [], root: AbsolutePath("/")), dependencies: dependencies)
    }
}

class ModuleTests: XCTestCase {
    /// Check that module dependencies appear in build order.
    func testDependencyOrder() throws {
        let c = try Module(name: "c")
        let b = try Module(name: "b", dependencies: [c])
        let a = try Module(name: "a", dependencies: [b])
        XCTAssertEqual(a.recursiveDependencies, [c, b])
    }

    static var allTests = [
        ("testDependencyOrder", testDependencyOrder),
    ]
}
