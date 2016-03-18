/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

@testable import Utility
import XCTest

class GitMoc: Git {
    static var mocVersion: String = "git version 2.5.4 (Apple Git-61)"
    override class var version: String! {
        return mocVersion
    }
}

class GitTests: XCTestCase {

    func testGitVersion() {
        XCTAssertEqual(GitMoc.majorVersionNumber, 2)

        GitMoc.mocVersion = "2.5.4"
        XCTAssertEqual(GitMoc.majorVersionNumber, 2)

        GitMoc.mocVersion = "git version 1.5.4"
        XCTAssertEqual(GitMoc.majorVersionNumber, 1)

        GitMoc.mocVersion = "1.25.4"
        XCTAssertEqual(GitMoc.majorVersionNumber, 1)
    }
}

extension GitTests {
    static var allTests : [(String, GitTests -> () throws -> Void)] {
        return [
                   ("testGitVersion", testGitVersion),
        ]
    }
}
