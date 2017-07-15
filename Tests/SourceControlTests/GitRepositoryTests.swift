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

    func testSubmoduleRead() throws {
        mktmpdir { path in
            let testRepoPath = path.appending(component: "test-repo")
            try makeDirectories(testRepoPath)
            initGitRepo(testRepoPath)

            let repoPath = path.appending(component: "repo")
            try makeDirectories(repoPath)
            initGitRepo(repoPath)

            try Process.checkNonZeroExit(
                args: Git.tool, "-C", repoPath.asString, "submodule", "add", testRepoPath.asString)
            let repo = GitRepository(path: repoPath)
            try repo.stageEverything()
            try repo.commit()
            // We should be able to read a repo which as a submdoule.
            _ = try repo.read(tree: try repo.resolveHash(treeish: "master"))
        }
    }

    /// Test the Git file system view.
    func testGitFileView() throws {
        mktmpdir { path in
            let testRepoPath = path.appending(component: "test-repo")
            try makeDirectories(testRepoPath)
            initGitRepo(testRepoPath)

            // Add a few files and a directory.
            let test1FileContents: ByteString = "Hello, world!"
            let test2FileContents: ByteString = "Hello, happy world!"
            let test3FileContents: ByteString = """
                #!/bin/sh
                set -e
                exit 0
                """
            try localFileSystem.writeFileContents(testRepoPath.appending(component: "test-file-1.txt"), bytes: test1FileContents)
            try localFileSystem.createDirectory(testRepoPath.appending(component: "subdir"))
            try localFileSystem.writeFileContents(testRepoPath.appending(components: "subdir", "test-file-2.txt"), bytes: test2FileContents)
            try localFileSystem.writeFileContents(testRepoPath.appending(component: "test-file-3.sh"), bytes: test3FileContents)
            try! Process.checkNonZeroExit(args: "chmod", "+x", testRepoPath.appending(component: "test-file-3.sh").asString)
            let testRepo = GitRepository(path: testRepoPath)
            try testRepo.stage(files: "test-file-1.txt", "subdir/test-file-2.txt", "test-file-3.sh")
            try testRepo.commit()
            try testRepo.tag(name: "test-tag")

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
            XCTAssert(!view.isExecutableFile(AbsolutePath("/does-not-exist")))
            XCTAssert(view.isExecutableFile(AbsolutePath("/test-file-3.sh")))

            // Check read of a directory.
            XCTAssertEqual(try view.getDirectoryContents(AbsolutePath("/")).sorted(), ["file.swift", "subdir", "test-file-1.txt", "test-file-3.sh"])
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
            let initialRevision = try GitRepository(path: testRepoPath).getCurrentRevision()

            // Add a couple files and a directory.
            try localFileSystem.writeFileContents(testRepoPath.appending(component: "test.txt"), bytes: "Hi")
            let testRepo = GitRepository(path: testRepoPath)
            try testRepo.stage(file: "test.txt")
            try testRepo.commit()
            try testRepo.tag(name: "test-tag")
            let currentRevision = try GitRepository(path: testRepoPath).getCurrentRevision()

            // Fetch the repository using the provider.
            let testClonePath = path.appending(component: "clone")
            let provider = GitRepositoryProvider()
            let repoSpec = RepositorySpecifier(url: testRepoPath.asString)
            try provider.fetch(repository: repoSpec, to: testClonePath)

            // Clone off a checkout.
            let checkoutPath = path.appending(component: "checkout")
            try provider.cloneCheckout(repository: repoSpec, at: testClonePath, to: checkoutPath, editable: false)
            // The remote of this checkout should point to the clone.
            XCTAssertEqual(try GitRepository(path: checkoutPath).remotes()[0].url, testClonePath.asString)

            let editsPath = path.appending(component: "edit")
            try provider.cloneCheckout(repository: repoSpec, at: testClonePath, to: editsPath, editable: true)
            // The remote of this checkout should point to the original repo.
            XCTAssertEqual(try GitRepository(path: editsPath).remotes()[0].url, testRepoPath.asString)

            // Check the working copies.
            for path in [checkoutPath, editsPath] {
                let workingCopy = try provider.openCheckout(at: path)
                try workingCopy.checkout(tag: "test-tag")
                XCTAssertEqual(try workingCopy.getCurrentRevision(), currentRevision)
                XCTAssert(localFileSystem.exists(path.appending(component: "test.txt")))
                try workingCopy.checkout(tag: "initial")
                XCTAssertEqual(try workingCopy.getCurrentRevision(), initialRevision)
                XCTAssert(!localFileSystem.exists(path.appending(component: "test.txt")))
            }
        }
    }

    func testFetch() throws {
        mktmpdir { path in
            // Create a repo.
            let testRepoPath = path.appending(component: "test-repo")
            try makeDirectories(testRepoPath)
            initGitRepo(testRepoPath, tag: "1.2.3")
            let repo = GitRepository(path: testRepoPath)
            XCTAssertEqual(repo.tags, ["1.2.3"])

            // Clone it somewhere.
            let testClonePath = path.appending(component: "clone")
            let provider = GitRepositoryProvider()
            let repoSpec = RepositorySpecifier(url: testRepoPath.asString)
            try provider.fetch(repository: repoSpec, to: testClonePath)
            let clonedRepo = provider.open(repository: repoSpec, at: testClonePath)
            XCTAssertEqual(clonedRepo.tags, ["1.2.3"])

            // Clone off a checkout.
            let checkoutPath = path.appending(component: "checkout")
            try provider.cloneCheckout(repository: repoSpec, at: testClonePath, to: checkoutPath, editable: false)
            let checkoutRepo = try provider.openCheckout(at: checkoutPath)
            XCTAssertEqual(checkoutRepo.tags, ["1.2.3"])

            // Add a new file to original repo.
            try localFileSystem.writeFileContents(testRepoPath.appending(component: "test.txt"), bytes: "Hi")
            let testRepo = GitRepository(path: testRepoPath)
            try testRepo.stage(file: "test.txt")
            try testRepo.commit()
            try testRepo.tag(name: "2.0.0")

            // Update the cloned repo.
            try clonedRepo.fetch()
            XCTAssertEqual(clonedRepo.tags.sorted(), ["1.2.3", "2.0.0"])

            // Update the checkout.
            try checkoutRepo.fetch()
            XCTAssertEqual(checkoutRepo.tags.sorted(), ["1.2.3", "2.0.0"])
        }
    }

    func testHasUnpushedCommits() throws {
        mktmpdir { path in
            // Create a repo.
            let testRepoPath = path.appending(component: "test-repo")
            try makeDirectories(testRepoPath)
            initGitRepo(testRepoPath)

            // Create a bare clone it somewhere because we want to later push into the repo.
            let testBareRepoPath = path.appending(component: "test-repo-bare")
            try systemQuietly([Git.tool, "clone", "--bare", testRepoPath.asString, testBareRepoPath.asString])

            // Clone it somewhere.
            let testClonePath = path.appending(component: "clone")
            let provider = GitRepositoryProvider()
            let repoSpec = RepositorySpecifier(url: testBareRepoPath.asString)
            try provider.fetch(repository: repoSpec, to: testClonePath)

            // Clone off a checkout.
            let checkoutPath = path.appending(component: "checkout")
            try provider.cloneCheckout(repository: repoSpec, at: testClonePath, to: checkoutPath, editable: true)
            let checkoutRepo = try provider.openCheckout(at: checkoutPath)

            XCTAssertFalse(try checkoutRepo.hasUnpushedCommits())
            // Add a new file to checkout.
            try localFileSystem.writeFileContents(checkoutPath.appending(component: "test.txt"), bytes: "Hi")
            let checkoutTestRepo = GitRepository(path: checkoutPath)
            try checkoutTestRepo.stage(file: "test.txt")
            try checkoutTestRepo.commit()

            // We should have commits which are not pushed.
            XCTAssert(try checkoutRepo.hasUnpushedCommits())
            // Push the changes and check again.
            try checkoutTestRepo.push(remote: "origin", branch: "master")
            XCTAssertFalse(try checkoutRepo.hasUnpushedCommits())
        }
    }

    func testSetRemote() {
        mktmpdir { path in
            // Create a repo.
            let testRepoPath = path.appending(component: "test-repo")
            try makeDirectories(testRepoPath)
            initGitRepo(testRepoPath)
            let repo = GitRepository(path: testRepoPath)

            // There should be no remotes currently.
            XCTAssert(try repo.remotes().isEmpty)

            // Add a remote via git cli.
            try systemQuietly([Git.tool, "-C", testRepoPath.asString, "remote", "add", "origin", "../foo"])
            // Test if it was added.
            XCTAssertEqual(Dictionary(items: try repo.remotes().map { ($0.0, $0.1) }), ["origin": "../foo"])
            // Change remote.
            try repo.setURL(remote: "origin", url: "../bar")
            XCTAssertEqual(Dictionary(items: try repo.remotes().map { ($0.0, $0.1) }), ["origin": "../bar"])
            // Try changing remote of non-existant remote.
            do {
                try repo.setURL(remote: "fake", url: "../bar")
                XCTFail("unexpected success")
            } catch ProcessResult.Error.nonZeroExit {}
        }
    }

    func testUncommitedChanges() throws {
        mktmpdir { path in
            // Create a repo.
            let testRepoPath = path.appending(component: "test-repo")
            try makeDirectories(testRepoPath)
            initGitRepo(testRepoPath)

            // Create a file (which we will modify later).
            try localFileSystem.writeFileContents(testRepoPath.appending(component: "test.txt"), bytes: "Hi")
            let repo = GitRepository(path: testRepoPath)
            try repo.stage(file: "test.txt")
            try repo.commit()

            XCTAssertFalse(repo.hasUncommitedChanges())

            // Modify the file in the repo.
            try localFileSystem.writeFileContents(repo.path.appending(component: "test.txt"), bytes: "Hello")
            XCTAssert(repo.hasUncommitedChanges())
        }
    }

    func testBranchOperations() throws {
        mktmpdir { path in
            // Create a repo.
            let testRepoPath = path.appending(component: "test-repo")
            try makeDirectories(testRepoPath)
            initGitRepo(testRepoPath)

            let repo = GitRepository(path: testRepoPath)
            var currentRevision = try repo.getCurrentRevision()
            // This is the default branch of a new repo.
            XCTAssert(repo.exists(revision: Revision(identifier: "master")))
            // Check a non existent revision.
            XCTAssertFalse(repo.exists(revision: Revision(identifier: "nonExistent")))
            // Checkout a new branch using command line.
            try systemQuietly([Git.tool, "-C", testRepoPath.asString, "checkout", "-b", "TestBranch1"])
            XCTAssert(repo.exists(revision: Revision(identifier: "TestBranch1")))
            XCTAssertEqual(try repo.getCurrentRevision(), currentRevision)

            // Make sure we're on the new branch right now.
            XCTAssertEqual(try repo.currentBranch(), "TestBranch1")

            // Checkout new branch using our API.
            currentRevision = try repo.getCurrentRevision()
            try repo.checkout(newBranch: "TestBranch2")
            XCTAssert(repo.exists(revision: Revision(identifier: "TestBranch2")))
            XCTAssertEqual(try repo.getCurrentRevision(), currentRevision)
            XCTAssertEqual(try repo.currentBranch(), "TestBranch2")
        }
    }

    func testCheckoutRevision() throws {
        mktmpdir { path in
            // Create a repo.
            let testRepoPath = path.appending(component: "test-repo")
            try makeDirectories(testRepoPath)
            initGitRepo(testRepoPath)
            let repo = GitRepository(path: testRepoPath)

            func createAndStageTestFile() throws {
                try localFileSystem.writeFileContents(testRepoPath.appending(component: "test.txt"), bytes: "Hi")
                try repo.stage(file: "test.txt")
            }

            try repo.checkout(revision: Revision(identifier: "master"))
            // Current branch must be master.
            XCTAssertEqual(try repo.currentBranch(), "master")
            // Create a new branch.
            try repo.checkout(newBranch: "TestBranch")
            XCTAssertEqual(try repo.currentBranch(), "TestBranch")
            // Create some random file.
            try createAndStageTestFile()
            XCTAssert(repo.hasUncommitedChanges())
            // Checkout current revision again, the test file should go away.
            let currentRevision = try repo.getCurrentRevision()
            try repo.checkout(revision: currentRevision)
            XCTAssertFalse(repo.hasUncommitedChanges())
            // We should be on detached head.
            XCTAssertEqual(try repo.currentBranch(), "HEAD")

            // Try again and checkout to a previous branch.
            try createAndStageTestFile()
            XCTAssert(repo.hasUncommitedChanges())
            try repo.checkout(revision: Revision(identifier: "TestBranch"))
            XCTAssertFalse(repo.hasUncommitedChanges())
            XCTAssertEqual(try repo.currentBranch(), "TestBranch")

            do {
                try repo.checkout(revision: Revision(identifier: "nonExistent"))
                XCTFail("Unexpected checkout success on non existent branch")
            } catch {}
        }
    }

    func testSubmodules() throws {
        mktmpdir { path in
            let provider = GitRepositoryProvider()

            // Create repos: foo and bar, foo will have bar as submodule and then later
            // the submodule ref will be updated in foo.
            let fooPath = path.appending(component: "foo-original")
            let fooSpecifier = RepositorySpecifier(url: fooPath.asString)
            let fooRepoPath = path.appending(component: "foo-repo")
            let fooWorkingPath = path.appending(component: "foo-working")
            let barPath = path.appending(component: "bar-original")
            let bazPath = path.appending(component: "baz-original")
            // Create the repos and add a file.
            for path in [fooPath, barPath, bazPath] {
                try makeDirectories(path)
                initGitRepo(path)
                try localFileSystem.writeFileContents(path.appending(component: "hello.txt"), bytes: "hello")
                let repo = GitRepository(path: path)
                try repo.stageEverything()
                try repo.commit()
            }
            let foo = GitRepository(path: fooPath)
            let bar = GitRepository(path: barPath)
            // The tag 1.0.0 does not contain the submodule. 
            try foo.tag(name: "1.0.0")

            // Fetch and clone repo foo.
            try provider.fetch(repository: fooSpecifier, to: fooRepoPath)
            try provider.cloneCheckout(repository: fooSpecifier, at: fooRepoPath, to: fooWorkingPath, editable: false)

            let fooRepo = GitRepository(path: fooRepoPath, isWorkingRepo: false)
            let fooWorkingRepo = GitRepository(path: fooWorkingPath)

            // Checkout the first tag which doesn't has submodule.
            try fooWorkingRepo.checkout(tag: "1.0.0")
            XCTAssertFalse(exists(fooWorkingPath.appending(component: "bar")))

            // Add submodule to foo and tag it as 1.0.1
            try foo.checkout(newBranch: "submodule")
            try systemQuietly([Git.tool, "-C", fooPath.asString, "submodule", "add", barPath.asString, "bar"])
            try foo.stageEverything()
            try foo.commit()
            try foo.tag(name: "1.0.1")

            // Update our bare and working repos.
            try fooRepo.fetch()
            try fooWorkingRepo.fetch()
            // Checkout the tag with submodule and expect submodules files to be present.
            try fooWorkingRepo.checkout(tag: "1.0.1")
            XCTAssertTrue(exists(fooWorkingPath.appending(components: "bar", "hello.txt")))
            // Checkout the tag without submodule and ensure that the submodule files are gone.
            try fooWorkingRepo.checkout(tag: "1.0.0")
            XCTAssertFalse(exists(fooWorkingPath.appending(components: "bar")))

            // Add something to bar.
            try localFileSystem.writeFileContents(barPath.appending(component: "bar.txt"), bytes: "hello")
            // Add a submodule too to check for recusive submodules.
            try systemQuietly([Git.tool, "-C", barPath.asString, "submodule", "add", bazPath.asString, "baz"])
            try bar.stageEverything()
            try bar.commit()

            // Update the ref of bar in foo and tag as 1.0.2
            try systemQuietly([Git.tool, "-C", fooPath.appending(component: "bar").asString, "pull"])
            try foo.stageEverything()
            try foo.commit()
            try foo.tag(name: "1.0.2")

            try fooRepo.fetch()
            try fooWorkingRepo.fetch()
            // We should see the new file we added in the submodule.
            try fooWorkingRepo.checkout(tag: "1.0.2")
            XCTAssertTrue(exists(fooWorkingPath.appending(components: "bar", "hello.txt")))
            XCTAssertTrue(exists(fooWorkingPath.appending(components: "bar", "bar.txt")))
            XCTAssertTrue(exists(fooWorkingPath.appending(components: "bar", "baz", "hello.txt")))

            // Sanity check.
            try fooWorkingRepo.checkout(tag: "1.0.0")
            XCTAssertFalse(exists(fooWorkingPath.appending(components: "bar")))
        }
    }

    static var allTests = [
        ("testBranchOperations", testBranchOperations),
        ("testCheckoutRevision", testCheckoutRevision),
        ("testCheckouts", testCheckouts),
        ("testFetch", testFetch),
        ("testGitFileView", testGitFileView),
        ("testGitRepositoryHash", testGitRepositoryHash),
        ("testHasUnpushedCommits", testHasUnpushedCommits),
        ("testProvider", testProvider),
        ("testRawRepository", testRawRepository),
        ("testRepositorySpecifier", testRepositorySpecifier),
        ("testSetRemote", testSetRemote),
        ("testSubmoduleRead", testSubmoduleRead),
        ("testSubmodules", testSubmodules),
        ("testUncommitedChanges", testUncommitedChanges),
    ]
}
