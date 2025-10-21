//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Foundation

import Basics
import SourceControl
import _InternalTestSupport
import Testing

struct InMemoryGitRepositoryTests {
    @Test
    func basics() throws {
        let fs = InMemoryFileSystem()
        let repo = InMemoryGitRepository(path: .root, fs: fs)

        try repo.createDirectory("/new-dir/subdir", recursive: true)
        #expect(!repo.hasUncommittedChanges())
        let filePath = AbsolutePath("/new-dir/subdir").appending("new-file.txt")

        try repo.writeFileContents(filePath, bytes: "one")
        #expect(try repo.readFileContents(filePath) == "one")
        #expect(repo.hasUncommittedChanges())

        let firstCommit = try repo.commit()
        #expect(!repo.hasUncommittedChanges())

        #expect(try repo.readFileContents(filePath) == "one")
        #expect(try fs.readFileContents(filePath) == "one")

        try repo.writeFileContents(filePath, bytes: "two")
        #expect(try repo.readFileContents(filePath) == "two")
        #expect(repo.hasUncommittedChanges())

        let secondCommit = try repo.commit()
        #expect(!repo.hasUncommittedChanges())
        #expect(try repo.readFileContents(filePath) == "two")

        try repo.writeFileContents(filePath, bytes: "three")
        #expect(repo.hasUncommittedChanges())
        #expect(try repo.readFileContents(filePath) == "three")

        try repo.checkout(revision: firstCommit)
        #expect(!repo.hasUncommittedChanges())
        #expect(try repo.readFileContents(filePath) == "one")
        #expect(try fs.readFileContents(filePath) == "one")

        try repo.checkout(revision: secondCommit)
        #expect(!repo.hasUncommittedChanges())
        #expect(try repo.readFileContents(filePath) == "two")

        #expect(try repo.getTags().isEmpty)
        try repo.tag(name: "2.0.0")
        #expect(try repo.getTags() == ["2.0.0"])
        #expect(!repo.hasUncommittedChanges())
        #expect(try repo.readFileContents(filePath) == "two")
        #expect(try fs.readFileContents(filePath) == "two")

        try repo.checkout(revision: firstCommit)
        #expect(!repo.hasUncommittedChanges())
        #expect(try repo.readFileContents(filePath) == "one")

        try repo.checkout(tag: "2.0.0")
        #expect(!repo.hasUncommittedChanges())
        #expect(try repo.readFileContents(filePath) == "two")
    }

    @Test
    func provider() async throws {
        let v1 = "1.0.0"
        let v2 = "2.0.0"
        let repo = InMemoryGitRepository(path: .root, fs: InMemoryFileSystem())

        let specifier = RepositorySpecifier(path: "/Foo")
        try repo.createDirectory("/new-dir/subdir", recursive: true)
        let filePath = AbsolutePath("/new-dir/subdir").appending("new-file.txt")
        try repo.writeFileContents(filePath, bytes: "one")
        try repo.commit()
        try repo.tag(name: v1)
        try repo.writeFileContents(filePath, bytes: "two")
        try repo.commit()
        try repo.tag(name: v2)

        let provider = InMemoryGitRepositoryProvider()
        provider.add(specifier: specifier, repository: repo)

        let fooRepoPath = AbsolutePath("/fooRepo")
        try await provider.fetch(repository: specifier, to: fooRepoPath)
        let fooRepo = try provider.open(repository: specifier, at: fooRepoPath)

        // Adding a new tag in original repo shouldn't show up in fetched repo.
        try repo.tag(name: "random")
        #expect(try fooRepo.getTags().sorted() == [v1, v2])
        #expect(fooRepo.exists(revision: try fooRepo.resolveRevision(tag: v1)))

        let fooCheckoutPath = AbsolutePath("/fooCheckout")
        #expect(!(try provider.workingCopyExists(at: fooCheckoutPath)))
        _ = try await provider.createWorkingCopy(repository: specifier, sourcePath: fooRepoPath, at: fooCheckoutPath, editable: false)
        #expect(try provider.workingCopyExists(at: fooCheckoutPath))
        let fooCheckout = try await provider.openWorkingCopy(at: fooCheckoutPath)

        #expect(try fooCheckout.getTags().sorted() == [v1, v2])
        #expect(fooCheckout.exists(revision: try fooCheckout.getCurrentRevision()))
        let checkoutRepo = try provider.openRepo(at: fooCheckoutPath)

        try fooCheckout.checkout(tag: v1)
        #expect(try checkoutRepo.readFileContents(filePath) == "one")

        try fooCheckout.checkout(tag: v2)
        #expect(try checkoutRepo.readFileContents(filePath) == "two")
    }
}
