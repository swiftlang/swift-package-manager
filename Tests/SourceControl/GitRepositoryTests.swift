/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import SourceControl
import Utility

import func POSIX.mkdtemp

class GitRepositoryTests: XCTestCase {
    /// Test the basic provider functions.
    func testProvider() {
        try! POSIX.mkdtemp(#function) { path in
            // Create a dummy repository to clone.
            let testRepoPath = Path.join(path, "test-repo")
            try! Utility.makeDirectories(testRepoPath)
            try! Git.runCommandQuietly([Git.tool, "-C", testRepoPath, "init"])
            try! Utility.fopen(Path.join(testRepoPath, "README.md"), mode: .write) { handle in
                try! fputs("dummy", handle)
            }
            try! Git.runCommandQuietly([Git.tool, "-C", testRepoPath, "add", "README.md"])
            try! Git.runCommandQuietly([Git.tool, "-C", testRepoPath, "commit", "-m", "Initial commit."])
            try! Git.runCommandQuietly([Git.tool, "-C", testRepoPath, "tag", "1.2.3"])

            // Test the provider.
            let testCheckoutPath = Path.join(path, "checkout")
            let provider = GitRepositoryProvider()
            let repoSpec = RepositorySpecifier(url: testRepoPath)
            try! provider.fetch(repository: repoSpec, to: testCheckoutPath)

            // Verify the checkout was made.
            XCTAssert(testCheckoutPath.exists)

            // Test the repository interface.
            let repository = provider.open(repository: repoSpec, at: testCheckoutPath)
            XCTAssertEqual(repository.tags, ["1.2.3"])
        }
    }

    static var allTests: [(String, (GitRepositoryTests) -> () throws -> Void)] {
        return [
            ("testProvider", testProvider),
        ]
    }
}
