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
    private var _fetched = [RepositorySpecifier]()
    private var fetchedLock = Lock() 

    var fetched: [RepositorySpecifier] {
        get {
            return fetchedLock.withLock {
                return _fetched
            }
        }
    }

    func fetching(handle: RepositoryManager.RepositoryHandle, to path: AbsolutePath) {
        fetchedLock.withLock {
            _fetched += [handle.repository]
        }
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
            let lookupExpectation = expectation(description: "Repository lookup expectation")

            manager.lookup(repository: dummyRepo) { result in
                guard case .success(let handle) = result else {
                    XCTFail("Could not get handle")
                    return
                }

                XCTAssertEqual(provider.numFetches, 0)
                XCTAssert(delegate.fetched.contains(dummyRepo))
            
                // We should always get back the same handle once fetched.
                XCTAssert(handle === (try? manager.lookupSynchronously(repository: dummyRepo)))
                XCTAssertEqual(provider.numFetches, 1)
            
                // Open the repository.
                let repository = try! handle.open()
                XCTAssertEqual(repository.tags, ["1.0.0"])

                // Create a checkout of the repository.
                let checkoutPath = path.appending(component: "checkout")
                try! handle.cloneCheckout(to: checkoutPath, editable: false)
            
                XCTAssert(localFileSystem.exists(checkoutPath.appending(component: "README.txt")))
                // Remove the repo.
                try! manager.remove(repository: dummyRepo)
                XCTAssert(localFileSystem.exists(checkoutPath))
                lookupExpectation.fulfill()
            }

            let badLookupExpectation = expectation(description: "Repository lookup expectation")
            // Get a bad repository.
            let badDummyRepo = RepositorySpecifier(url: "badDummy")
            manager.lookup(repository: badDummyRepo) { result in
                guard case .failure(let error) = result else {
                    XCTFail("Unexpected success")
                    return
                }
                XCTAssertEqual(error.underlyingError as? DummyError, DummyError.invalidRepository)
                badLookupExpectation.fulfill()
            }

            waitForExpectations(timeout: 1)
            // We should have tried fetching these two.
            XCTAssertEqual(Set(delegate.fetched), [dummyRepo, badDummyRepo])
        }
    }

    func testSyncLookup() throws {
        mktmpdir { path in
            let provider = DummyRepositoryProvider()
            let delegate = DummyRepositoryManagerDelegate()
            let manager = RepositoryManager(path: path, provider: provider, delegate: delegate)
            let dummyRepo = RepositorySpecifier(url: "dummy")
            let handle = try manager.lookupSynchronously(repository: dummyRepo)
            // Relookup should return same instance.
            XCTAssert(handle === (try? manager.lookupSynchronously(repository: dummyRepo)))
            // And async lookup should also return same instance.
            let lookupExpectation = expectation(description: "Repository lookup expectation")
            manager.lookup(repository: dummyRepo) { result in
                XCTAssert(handle === (try? result.dematerialize()))
                lookupExpectation.fulfill()
            }
            waitForExpectations(timeout: 1)
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

                _ = try manager.lookupSynchronously(repository: dummyRepo)

                XCTAssertEqual(delegate.fetched, [dummyRepo])
            }
            // We should have performed one fetch.
            XCTAssertEqual(provider.numClones, 1)
            XCTAssertEqual(provider.numFetches, 0)

            // Create a new manager, and fetch.
            do {
                let delegate = DummyRepositoryManagerDelegate()
                let manager = RepositoryManager(path: path, provider: provider, delegate: delegate)
                let dummyRepo = RepositorySpecifier(url: "dummy")
                _ = try manager.lookupSynchronously(repository: dummyRepo)
                // This time fetch shouldn't be called.
                XCTAssertEqual(delegate.fetched, [])
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

                _ = try manager.lookupSynchronously(repository: dummyRepo)

                XCTAssertEqual(delegate.fetched, [dummyRepo])
            }
            // We should have re-fetched.
            XCTAssertEqual(provider.numClones, 2)
            XCTAssertEqual(provider.numFetches, 1)
        }
    }

    static var allTests = [
        ("testBasics", testBasics),
        ("testPersistence", testPersistence),
        ("testSyncLookup", testSyncLookup),
    ]
}
