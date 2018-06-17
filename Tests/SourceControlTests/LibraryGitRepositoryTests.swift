/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import SourceControl
import Utility

import TestSupport

@testable import class SourceControl.GitRepository

class LibraryGitRepositoryTests: XCTestCase {
    /// Test the basic provider functions.
    func testProvider() throws {
        mktmpdir { path in
            let testRepoPath = path.appending(component: "test-repo")
            try! makeDirectories(testRepoPath)
            initGitRepo(testRepoPath, tag: "1.2.3")

            // Test the provider.
            let testCheckoutPath = path.appending(component: "checkout")
            let provider = LibraryGitRepositoryProvider()
            let repoSpec = RepositorySpecifier(url: testRepoPath.asString)
            try provider.fetch(repository: repoSpec, to: testCheckoutPath)

            // Verify the checkout was made.
            XCTAssert(exists(testCheckoutPath))

            // Test the repository interface.
            let repository = provider.open(repository: repoSpec, at: testCheckoutPath)
            let tags = repository.tags
            XCTAssertEqual(repository.tags, ["1.2.3"])

            let revision = try repository.resolveRevision(tag: tags.first ?? "<invalid>")
            // FIXME: It would be nice if we had a deterministic hash here...
            XCTAssertEqual(revision.identifier,
                           try Process.popen(
                            args: Git.tool, "-C", testRepoPath.asString, "rev-parse", "--verify", "1.2.3").utf8Output().chomp())
            if let revision = try? repository.resolveRevision(tag: "<invalid>") {
                XCTFail("unexpected resolution of invalid tag to \(revision)")
            }

            let master = try repository.resolveRevision(identifier: "master")

            XCTAssertEqual(master.identifier,
                           try Process.checkNonZeroExit(
                            args: Git.tool, "-C", testRepoPath.asString, "rev-parse", "--verify", "master").chomp())

            // Check that git hashes resolve to themselves.
            let masterIdentifier = try repository.resolveRevision(identifier: master.identifier)
            XCTAssertEqual(master.identifier, masterIdentifier.identifier)

            // Check that invalid identifier doesn't resolve.
            if let revision = try? repository.resolveRevision(identifier: "invalid") {
                XCTFail("unexpected resolution of invalid identifier to \(revision)")
            }
        }
    }
}
