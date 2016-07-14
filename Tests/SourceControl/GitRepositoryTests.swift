/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import SourceControl
import Utility


class GitRepositoryTests: XCTestCase {
    /// Test the basic provider functions.
    func testProvider() {
        mktmpdir { path in
            let testRepoPath = path.appending("test-repo")
            try! Utility.makeDirectories(testRepoPath.asString)
            initGitRepo(testRepoPath, tag: "1.2.3")

            // Test the provider.
            let testCheckoutPath = path.appending("checkout")
            let provider = GitRepositoryProvider()
            let repoSpec = RepositorySpecifier(url: testRepoPath.asString)
            try! provider.fetch(repository: repoSpec, to: testCheckoutPath)

            // Verify the checkout was made.
            XCTAssert(testCheckoutPath.asString.exists)

            // Test the repository interface.
            let repository = provider.open(repository: repoSpec, at: testCheckoutPath)
            XCTAssertEqual(repository.tags, ["1.2.3"])
        }
    }

    static var allTests = [
        ("testProvider", testProvider),
    ]
}
