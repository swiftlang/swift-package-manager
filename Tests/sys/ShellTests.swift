/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
@testable import POSIX

class ShellTests: XCTestCase, XCTestCaseProvider {

    var allTests : [(String, () -> ())] {
        return [
            ("test_popen", test_popen),
        ]
    }
    
    func test_popen() {
        XCTAssertEqual(try! popen(["echo", "foo"]), "foo\n")
        XCTAssertGreaterThan(try! popen(["cat", "/etc/passwd"]).characters.count, 4096)
    }
}
