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

class InMemoryGitRepositoryTests: XCTestCase {
    func testBasics() throws {
        let fs = InMemoryFileSystem()
        let repo = InMemoryGitRepository(path: .root, fs: fs)

        try repo.createDirectory(AbsolutePath("/new-dir/subdir"), recursive: true)
        XCTAssertTrue(!repo.hasUncommitedChanges())
        let filePath = AbsolutePath("/new-dir/subdir").appending(component: "new-file.txt")

        try repo.writeFileContents(filePath, bytes: "one")
        XCTAssertEqual(try repo.readFileContents(filePath), "one")
        XCTAssertTrue(repo.hasUncommitedChanges())

        let firstCommit = repo.commit()
        XCTAssertTrue(!repo.hasUncommitedChanges())

        XCTAssertEqual(try repo.readFileContents(filePath), "one")
        XCTAssertEqual(try fs.readFileContents(filePath), "one")

        try repo.writeFileContents(filePath, bytes: "two")
        XCTAssertEqual(try repo.readFileContents(filePath), "two")
        XCTAssertTrue(repo.hasUncommitedChanges())

        let secondCommit = repo.commit()
        XCTAssertTrue(!repo.hasUncommitedChanges())
        XCTAssertEqual(try repo.readFileContents(filePath), "two")

        try repo.writeFileContents(filePath, bytes: "three")
        XCTAssertTrue(repo.hasUncommitedChanges())
        XCTAssertEqual(try repo.readFileContents(filePath), "three")

        try repo.checkout(revision: firstCommit)
        XCTAssertTrue(!repo.hasUncommitedChanges())
        XCTAssertEqual(try repo.readFileContents(filePath), "one")
        XCTAssertEqual(try fs.readFileContents(filePath), "one")

        try repo.checkout(revision: secondCommit)
        XCTAssertTrue(!repo.hasUncommitedChanges())
        XCTAssertEqual(try repo.readFileContents(filePath), "two")

        XCTAssert(repo.tags.isEmpty)
        try repo.tag(name: "2.0.0")
        XCTAssertEqual(repo.tags, ["2.0.0"])
        XCTAssertTrue(!repo.hasUncommitedChanges())
        XCTAssertEqual(try repo.readFileContents(filePath), "two")
        XCTAssertEqual(try fs.readFileContents(filePath), "two")

        try repo.checkout(revision: firstCommit)
        XCTAssertTrue(!repo.hasUncommitedChanges())
        XCTAssertEqual(try repo.readFileContents(filePath), "one")

        try repo.checkout(tag: "2.0.0")
        XCTAssertTrue(!repo.hasUncommitedChanges())
        XCTAssertEqual(try repo.readFileContents(filePath), "two")
    }

    func testProvider() throws {
        let v1 = "1.0.0"
        let v2 = "2.0.0"
        let repo = InMemoryGitRepository(path: .root, fs: InMemoryFileSystem())

        let specifier = RepositorySpecifier(url: "/foo")
        try repo.createDirectory(AbsolutePath("/new-dir/subdir"), recursive: true)
        let filePath = AbsolutePath("/new-dir/subdir").appending(component: "new-file.txt")
        try repo.writeFileContents(filePath, bytes: "one")
        repo.commit()
        try repo.tag(name: v1)
        try repo.writeFileContents(filePath, bytes: "two")
        repo.commit()
        try repo.tag(name: v2)

        let provider = InMemoryGitRepositoryProvider()
        provider.add(specifier: specifier, repository: repo)

        let fooRepoPath = AbsolutePath("/fooRepo")
        try provider.fetch(repository: specifier, to: fooRepoPath)
        let fooRepo = try provider.open(repository: specifier, at: fooRepoPath)

        // Adding a new tag in original repo shouldn't show up in fetched repo.
        try repo.tag(name: "random")
        XCTAssertEqual(fooRepo.tags.sorted(), [v1, v2])
        XCTAssert(fooRepo.exists(revision: try fooRepo.resolveRevision(tag: v1)))

        let fooCheckoutPath = AbsolutePath("/fooCheckout")
        try provider.cloneCheckout(repository: specifier, at: fooRepoPath, to: fooCheckoutPath, editable: false)
        let fooCheckout = try provider.openCheckout(at: fooCheckoutPath)

        XCTAssertEqual(fooCheckout.tags.sorted(), [v1, v2])
        XCTAssert(fooCheckout.exists(revision: try fooCheckout.getCurrentRevision()))
        let checkoutRepo = provider.openRepo(at: fooCheckoutPath)

        try fooCheckout.checkout(tag: v1)
        XCTAssertEqual(try checkoutRepo.readFileContents(filePath), "one")

        try fooCheckout.checkout(tag: v2)
        XCTAssertEqual(try checkoutRepo.readFileContents(filePath), "two")
    }

    static var allTests = [
        ("testBasics", testBasics),
        ("testProvider", testProvider),
    ]
}
