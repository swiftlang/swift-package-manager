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

@testable import class SourceControl.GitRepository

class GitRepositoryTests: XCTestCase {
    /// Test the basic provider functions.
    func testProvider() throws {
        mktmpdir { path in
            let testRepoPath = path.appending("test-repo")
            try! makeDirectories(testRepoPath)
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
            let tags = repository.tags
            XCTAssertEqual(repository.tags, ["1.2.3"])

            let revision = try repository.resolveRevision(tag: tags.first ?? "<invalid>")
            // FIXME: It would be nice if we had a deterministic hash here...
            XCTAssertEqual(revision.identifier, try Git.runPopen([Git.tool, "-C", testRepoPath.asString, "rev-parse", "--verify", "1.2.3"]).chomp())
            if let revision = try? repository.resolveRevision(tag: "<invalid>") {
                XCTFail("unexpected resolution of invalid tag to \(revision)")
            }
        }
    }

    /// Check hash validation.
    func testGitRepositoryHash() throws {
        let validHash = "0123456789012345678901234567890123456789"
        XCTAssertNotEqual(GitRepository.Hash(validHash), nil)
        
        let invalidHexHash = validHash + "1"
        XCTAssertEqual(GitRepository.Hash(invalidHexHash), nil)
        
        let invalidNonHexHash = "012345678901234567890123456789012345678!"
        XCTAssertEqual(GitRepository.Hash(invalidNonHexHash), nil)
    }
    
    /// Check raw repository facilities.
    func testRawRepository() throws {
        mktmpdir { path in
            let testRepoPath = path.appending("test-repo")
            try! makeDirectories(testRepoPath)
            initGitRepo(testRepoPath, tag: "1.2.3")

            let repo = GitRepository(path: testRepoPath)
            XCTAssertEqual(try repo.resolveHash(treeish: "1.2.3"),
                           try repo.resolveHash(treeish: "master"))
        }
    }

    static var allTests = [
        ("testProvider", testProvider),
        ("testGitRepositoryHash", testGitRepositoryHash),
        ("testRawRepository", testRawRepository),
    ]
}
