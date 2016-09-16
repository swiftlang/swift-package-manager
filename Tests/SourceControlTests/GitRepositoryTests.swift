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

import TestSupport

@testable import class SourceControl.GitRepository

class GitRepositoryTests: XCTestCase {
    /// Test the basic provider functions.
    func testRepositorySpecifier() {
        let a = RepositorySpecifier(url: "a")
        let b = RepositorySpecifier(url: "b")
        let a2 = RepositorySpecifier(url: "a")
        XCTAssertEqual(a, a)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a, a2)
        XCTAssertEqual(Set([a]), Set([a2]))
    }
        
    /// Test the basic provider functions.
    func testProvider() throws {
        mktmpdir { path in
            let testRepoPath = path.appending(component: "test-repo")
            try! makeDirectories(testRepoPath)
            initGitRepo(testRepoPath, tag: "1.2.3")

            // Test the provider.
            let testCheckoutPath = path.appending(component: "checkout")
            let provider = GitRepositoryProvider()
            let repoSpec = RepositorySpecifier(url: testRepoPath.asString)
            try! provider.fetch(repository: repoSpec, to: testCheckoutPath)

            // Verify the checkout was made.
            XCTAssert(exists(testCheckoutPath))

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
    ///
    /// In order to be stable, this test uses a static test git repository in
    /// `Inputs`, which has known commit hashes. See the `construct.sh` script
    /// contained within it for more information.
    func testRawRepository() throws {
        mktmpdir { path in
            // Unarchive the static test repository.
            let inputArchivePath = AbsolutePath(#file).parentDirectory.appending(components: "Inputs", "TestRepo.tgz")
            try systemQuietly(["tar", "-x", "-v", "-C", path.asString, "-f", inputArchivePath.asString])
            let testRepoPath = path.appending(component: "TestRepo")

            // Check hash resolution.
            let repo = GitRepository(path: testRepoPath)
            XCTAssertEqual(try repo.resolveHash(treeish: "1.0", type: "commit"),
                           try repo.resolveHash(treeish: "master"))

            // Get the initial commit.
            let initialCommitHash = try repo.resolveHash(treeish: "a8b9fcb")
            XCTAssertEqual(initialCommitHash, GitRepository.Hash("a8b9fcbf893b3b02c0196609059ebae37aeb7f0b"))

            // Check commit loading.
            let initialCommit = try repo.read(commit: initialCommitHash)
            XCTAssertEqual(initialCommit.hash, initialCommitHash)
            XCTAssertEqual(initialCommit.tree, GitRepository.Hash("9d463c3b538619448c5d2ecac379e92f075a8976"))

            // Check tree loading.
            let initialTree = try repo.read(tree: initialCommit.tree)
            XCTAssertEqual(initialTree.hash, initialCommit.tree)
            XCTAssertEqual(initialTree.contents.count, 1)
            guard let readmeEntry = initialTree.contents.first else { return XCTFail() }
            XCTAssertEqual(readmeEntry.hash, GitRepository.Hash("92513075b3491a54c45a880be25150d92388e7bc"))
            XCTAssertEqual(readmeEntry.type, .blob)
            XCTAssertEqual(readmeEntry.name, "README.txt")

            // Check loading of odd names.
            //
            // This is a commit which has a subdirectory 'funny-names' with
            // paths with special characters.
            let funnyNamesCommit = try repo.read(commit: repo.resolveHash(treeish: "a7b19a7"))
            let funnyNamesRoot = try repo.read(tree: funnyNamesCommit.tree)
            XCTAssertEqual(funnyNamesRoot.contents.map{ $0.name }, ["README.txt", "funny-names", "subdir"])
            guard funnyNamesRoot.contents.count == 3 else { return XCTFail() }

            // FIXME: This isn't yet supported.
            let funnyNamesSubdirEntry = funnyNamesRoot.contents[1]
            XCTAssertEqual(funnyNamesSubdirEntry.type, .tree)
            if let _ = try? repo.read(tree: funnyNamesSubdirEntry.hash) {
                XCTFail("unexpected success reading tree with funny names")
            }
       }
    }

    /// Test the Git file system view.
    func testGitFileView() throws {
        mktmpdir { path in
            let testRepoPath = path.appending(component: "test-repo")
            try makeDirectories(testRepoPath)
            initGitRepo(testRepoPath)

            // Add a couple files and a directory.
            let test1FileContents: ByteString = "Hello, world!"
            let test2FileContents: ByteString = "Hello, happy world!"
            try localFileSystem.writeFileContents(testRepoPath.appending(component: "test-file-1.txt"), bytes: test1FileContents)
            try localFileSystem.createDirectory(testRepoPath.appending(component: "subdir"))
            try localFileSystem.writeFileContents(testRepoPath.appending(components: "subdir", "test-file-2.txt"), bytes: test2FileContents)
            try systemQuietly([Git.tool, "-C", testRepoPath.asString, "add", "test-file-1.txt", "subdir/test-file-2.txt"])
            try systemQuietly([Git.tool, "-C", testRepoPath.asString, "commit", "-m", "Add some files."])
            try tagGitRepo(testRepoPath, tag: "test-tag")

            // Get the the repository via the provider. the provider.
            let testClonePath = path.appending(component: "clone")
            let provider = GitRepositoryProvider()
            let repoSpec = RepositorySpecifier(url: testRepoPath.asString)
            try provider.fetch(repository: repoSpec, to: testClonePath)
            let repository = provider.open(repository: repoSpec, at: testClonePath)

            // Get and test the file system view.
            let view = try repository.openFileView(revision: repository.resolveRevision(tag: "test-tag"))

            // Check basic predicates.
            XCTAssert(view.isDirectory(AbsolutePath("/")))
            XCTAssert(view.isDirectory(AbsolutePath("/subdir")))
            XCTAssert(!view.isDirectory(AbsolutePath("/does-not-exist")))
            XCTAssert(view.exists(AbsolutePath("/test-file-1.txt")))
            XCTAssert(!view.exists(AbsolutePath("/does-not-exist")))
            XCTAssert(view.isFile(AbsolutePath("/test-file-1.txt")))
            XCTAssert(!view.isSymlink(AbsolutePath("/test-file-1.txt")))

            // Check read of a directory.
            XCTAssertEqual(try view.getDirectoryContents(AbsolutePath("/")).sorted(), ["file.swift", "subdir", "test-file-1.txt"])
            XCTAssertEqual(try view.getDirectoryContents(AbsolutePath("/subdir")).sorted(), ["test-file-2.txt"])
            XCTAssertThrows(FileSystemError.isDirectory) {
                _ = try view.readFileContents(AbsolutePath("/subdir"))
            }

            // Check read versus root.
            XCTAssertThrows(FileSystemError.isDirectory) {
                _ = try view.readFileContents(AbsolutePath("/"))
            }

            // Check read through a non-directory.
            XCTAssertThrows(FileSystemError.notDirectory) {
                _ = try view.getDirectoryContents(AbsolutePath("/test-file-1.txt"))
            }
            XCTAssertThrows(FileSystemError.notDirectory) {
                _ = try view.readFileContents(AbsolutePath("/test-file-1.txt/thing"))
            }
            
            // Check read/write into a missing directory.
            XCTAssertThrows(FileSystemError.noEntry) {
                _ = try view.getDirectoryContents(AbsolutePath("/does-not-exist"))
            }
            XCTAssertThrows(FileSystemError.noEntry) {
                _ = try view.readFileContents(AbsolutePath("/does/not/exist"))
            }

            // Check read of a file.
            XCTAssertEqual(try view.readFileContents(AbsolutePath("/test-file-1.txt")), test1FileContents)
            XCTAssertEqual(try view.readFileContents(AbsolutePath("/subdir/test-file-2.txt")), test2FileContents)
        }
    }

    /// Test the handling of local checkouts.
    func testCheckouts() throws {
        mktmpdir { path in
            // Create a test repository.
            let testRepoPath = path.appending(component: "test-repo")
            try makeDirectories(testRepoPath)
            initGitRepo(testRepoPath, tag: "initial")
            let initialRevision = Git.Repo(path: testRepoPath)!.sha

            // Add a couple files and a directory.
            try localFileSystem.writeFileContents(testRepoPath.appending(component: "test.txt"), bytes: "Hi")
            try systemQuietly([Git.tool, "-C", testRepoPath.asString, "add", "test.txt"])
            try systemQuietly([Git.tool, "-C", testRepoPath.asString, "commit", "-m", "Add some files."])
            try tagGitRepo(testRepoPath, tag: "test-tag")
            let currentRevision = Git.Repo(path: testRepoPath)!.sha

            // Fetch the repository using the provider.
            let testClonePath = path.appending(component: "clone")
            let provider = GitRepositoryProvider()
            let repoSpec = RepositorySpecifier(url: testRepoPath.asString)
            try provider.fetch(repository: repoSpec, to: testClonePath)

            // Clone off a checkout.
            let checkoutPath = path.appending(component: "checkout")
            try provider.cloneCheckout(repository: repoSpec, at: testClonePath, to: checkoutPath)

            // Check the working copy.
            let workingCopy = try provider.openCheckout(at: checkoutPath)
            try workingCopy.checkout(tag: "test-tag")
            XCTAssertEqual(try workingCopy.getCurrentRevision().identifier, currentRevision)
            XCTAssert(localFileSystem.exists(checkoutPath.appending(component: "test.txt")))
            try workingCopy.checkout(tag: "initial")
            XCTAssertEqual(try workingCopy.getCurrentRevision().identifier, initialRevision)
            XCTAssert(!localFileSystem.exists(checkoutPath.appending(component: "test.txt")))
        }
    }

    static var allTests = [
        ("testRepositorySpecifier", testRepositorySpecifier),
        ("testProvider", testProvider),
        ("testGitRepositoryHash", testGitRepositoryHash),
        ("testRawRepository", testRawRepository),
        ("testGitFileView", testGitFileView),
        ("testCheckouts", testCheckouts),
    ]
}
