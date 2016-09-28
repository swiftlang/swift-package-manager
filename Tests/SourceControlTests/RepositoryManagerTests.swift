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

import TestSupport

@testable import class SourceControl.RepositoryManager

private enum DummyError: Swift.Error {
    case invalidRepository
}

private class DummyRepository: Repository {
    var tags: [String] = ["1.0.0"]
    unowned let provider: DummyRepositoryProvider

    init(provider: DummyRepositoryProvider) {
        self.provider = provider
    }

    func resolveRevision(tag: String) throws -> Revision {
        fatalError("unexpected API call")
    }

    func exists(revision: Revision) -> Bool {
        fatalError("unexpected API call")
    }

    func fetch() throws {
        provider.numFetches += 1
    }

    func openFileView(revision: Revision) throws -> FileSystem {
        fatalError("unexpected API call")
    }
}

private class DummyRepositoryProvider: RepositoryProvider {
    var numClones = 0
    var numFetches = 0
    
    func fetch(repository: RepositorySpecifier, to path: AbsolutePath) throws {
        assert(!localFileSystem.exists(path))
        try! localFileSystem.writeFileContents(path, bytes: ByteString(encodingAsUTF8: repository.url))

        numClones += 1
        
        // We only support one dummy URL.
        let basename = repository.url.components(separatedBy: "/").last!
        if basename != "dummy" {
            throw DummyError.invalidRepository
        }
    }

    func open(repository: RepositorySpecifier, at path: AbsolutePath) -> Repository {
        return DummyRepository(provider: self)
    }

    func cloneCheckout(repository: RepositorySpecifier, at sourcePath: AbsolutePath, to destinationPath: AbsolutePath, editable: Bool) throws {
        try localFileSystem.createDirectory(destinationPath)
        try localFileSystem.writeFileContents(destinationPath.appending(component: "README.txt"), bytes: "Hi")
    }

    func openCheckout(at path: AbsolutePath) throws -> WorkingCheckout {
        fatalError("unsupported")
    }
}

private class DummyRepositoryManagerDelegate: RepositoryManagerDelegate {
    var fetched = [RepositorySpecifier]()

    func fetching(handle: RepositoryManager.RepositoryHandle, to path: AbsolutePath) {
        fetched += [handle.repository]
    }
}

class RepositoryManagerTests: XCTestCase {
    func testBasics() throws {
        mktmpdir { path in
            let provider = DummyRepositoryProvider()
            let delegate = DummyRepositoryManagerDelegate()
            let manager = RepositoryManager(path: path, provider: provider, delegate: delegate)

            // Check that we can "fetch" a repository.
            let dummyRepo = RepositorySpecifier(url: "dummy")
            let handle = manager.lookup(repository: dummyRepo)
            XCTAssertEqual(provider.numFetches, 0)

            XCTAssertEqual(delegate.fetched, [dummyRepo])

            // We should always get back the same handle once fetched.
            XCTAssert(handle === manager.lookup(repository: dummyRepo))
            XCTAssertEqual(provider.numFetches, 1)
            
            // Validate that the repo is available.
            XCTAssertTrue(handle.isAvailable)

            // Open the repository.
            let repository = try handle.open()
            XCTAssertEqual(repository.tags, ["1.0.0"])

            // Create a checkout of the repository.
            let checkoutPath = path.appending(component: "checkout")
            try handle.cloneCheckout(to: checkoutPath, editable: false)
            XCTAssert(localFileSystem.exists(checkoutPath.appending(component: "README.txt")))

            XCTAssertEqual(delegate.fetched, [dummyRepo])
            // Remove the repo.
            try manager.remove(repository: dummyRepo)
            XCTAssert(localFileSystem.exists(checkoutPath))

            // Get a bad repository.
            let badDummyRepo = RepositorySpecifier(url: "badDummy")
            let badHandle = manager.lookup(repository: badDummyRepo)
            XCTAssertEqual(provider.numFetches, 1)

            XCTAssertEqual(delegate.fetched, [dummyRepo, badDummyRepo])

            // Validate that the repo is unavailable.
            XCTAssertFalse(badHandle.isAvailable)
        }
    }

    /// Check the behavior of the observer of repository status.
    func testObserver() {
        mktmpdir { path in
            let delegate = DummyRepositoryManagerDelegate()
            let manager = RepositoryManager(path: path, provider: DummyRepositoryProvider(), delegate: delegate)
            let dummyRepo = RepositorySpecifier(url: "dummy")
            let handle = manager.lookup(repository: dummyRepo)

            XCTAssertEqual(delegate.fetched, [dummyRepo])

            var wasAvailable: Bool? = nil
            handle.addObserver { handle in
                wasAvailable = handle.isAvailable
            }

            XCTAssertEqual(wasAvailable, true)
        }
    }

    /// Check that the manager is persistent.
    func testPersistence() {
        mktmpdir { path in
            let provider = DummyRepositoryProvider()

            // Do the initial fetch.
            do {
                let delegate = DummyRepositoryManagerDelegate()
                let manager = RepositoryManager(path: path, provider: provider, delegate: delegate)
                let dummyRepo = RepositorySpecifier(url: "dummy")
                let handle = manager.lookup(repository: dummyRepo)
                XCTAssertEqual(delegate.fetched, [dummyRepo])
                // FIXME: Wait for repo to become available.
                XCTAssertTrue(handle.isAvailable)
            }
            // We should have performed one fetch.
            XCTAssertEqual(provider.numClones, 1)
            XCTAssertEqual(provider.numFetches, 0)

            // Create a new manager, and fetch.
            do {
                let delegate = DummyRepositoryManagerDelegate()
                let manager = RepositoryManager(path: path, provider: provider, delegate: delegate)
                let dummyRepo = RepositorySpecifier(url: "dummy")
                let handle = manager.lookup(repository: dummyRepo)
                // This time fetch shouldn't be called.
                XCTAssertEqual(delegate.fetched, [])
                // FIXME: Wait for repo to become available.
                XCTAssertTrue(handle.isAvailable)
            }
            // We shouldn't have done a new fetch.
            XCTAssertEqual(provider.numClones, 1)
            XCTAssertEqual(provider.numFetches, 1)

            // Manually destroy the manager state, and check it still works.
            do {
                let delegate = DummyRepositoryManagerDelegate()
                var manager = RepositoryManager(path: path, provider: provider, delegate: delegate)
                try! removeFileTree(manager.statePath)
                manager = RepositoryManager(path: path, provider: provider, delegate: delegate)
                let dummyRepo = RepositorySpecifier(url: "dummy")
                let handle = manager.lookup(repository: dummyRepo)
                XCTAssertEqual(delegate.fetched, [dummyRepo])
                // FIXME: Wait for repo to become available.
                XCTAssertTrue(handle.isAvailable)
            }
            // We should have re-fetched.
            XCTAssertEqual(provider.numClones, 2)
            XCTAssertEqual(provider.numFetches, 1)
        }
    }

    static var allTests = [
        ("testBasics", testBasics),
        ("testObserver", testObserver),
        ("testPersistence", testPersistence),
    ]
}
