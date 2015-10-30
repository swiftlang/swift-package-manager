/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import dep
import sys
import XCTest

class FunctionalGetTests: SandboxTestCase, XCTestCaseProvider {

    var allTests : [(String, () -> ())] {
        return [
            ("testDealerBuild", testDealerBuild),
            ("testExternalDeps", testExternalDeps)
        ]
    }

    func testDealerBuild() {
        testSwiftGet(fixtureName: "101_mattts_dealer") { prefix, baseURL, executeSwiftGet in
            XCTAssertEqual(try! executeSwiftGet("\(baseURL)/app"), 0)
        }
    }

    func testExternalDeps() {
        testSwiftGet(fixtureName: "100_external_deps") { prefix, baseURL, executeSwiftGet in
            XCTAssertEqual(try! executeSwiftGet("\(baseURL)/Bar"), 0)
            XCTAssertTrue(Path.join(prefix, "Foo-1.2.3").isDirectory)
            XCTAssertTrue(Path.join(prefix, "Bar-1.2.3").isDirectory)
        }
    }
}
