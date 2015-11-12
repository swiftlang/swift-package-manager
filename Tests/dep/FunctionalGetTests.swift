/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func POSIX.popen
import XCTest

class FunctionalGetTests: XCTestCase, XCTestCaseProvider {

    var allTests : [(String, () -> ())] {
        return [
            ("test_get_ExternalDeps", test_get_ExternalDeps),
            ("test_get_DealerBuild", test_get_DealerBuild),
            ("test_get_DealerBuildOutput", test_get_DealerBuildOutput)
        ]
    }

    func test_get_ExternalDeps() {
        fixture(name: "100_external_deps") { prefix in
            mktmpdir {
                XCTAssertNotNil(try? executeSwiftGet("\(prefix)/Bar"))
                XCTAssertTrue("Foo-1.2.3".isDirectory)
                XCTAssertTrue("Bar-1.2.3".isDirectory)
            }
        }
    }

    // 25: Build Mattt's Dealer
    func test_get_DealerBuild() {
        fixture(name: "101_mattts_dealer") { prefix in
            mktmpdir {
                XCTAssertNotNil(try? executeSwiftGet("\(prefix)/app"))
            }
        }
    }

    // 25: Build Mattt's Dealer
    func test_get_DealerBuildOutput() {
        fixture(name: "102_mattts_dealer") { prefix in
            mktmpdir {
                XCTAssertNotNil(try? executeSwiftGet("\(prefix)/app"))
                let output = try POSIX.popen(["app-1.2.3/Dealer"])
                XCTAssertEqual(output, "♣︎K\n♣︎Q\n♣︎J\n♣︎10\n♣︎9\n♣︎8\n♣︎7\n♣︎6\n♣︎5\n♣︎4\n")
            }
        }
    }
}
