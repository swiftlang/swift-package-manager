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

import TestSupport

@testable import class SourceControl.RepositoryManager

extension RepositoryManager {
    fileprivate func lookupSynchronously(repository: RepositorySpecifier) throws -> RepositoryHandle {
        return try await { self.lookup(repository: repository, completion: $0) }
    }
}

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

    func resolveRevision(identifier: String) throws -> Revision {
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
    var numFetches: Int {
        get {
            return fetchesLock.withLock {
                return _numFetches
            }
        }
        set {
            fetchesLock.withLock {
                _numFetches = newValue
            }
        }
    }
    private var fetchesLock = Lock()
    var _numFetches = 0
    
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
    private var _willFetch = [RepositorySpecifier]()
    private var _didFetch = [RepositorySpecifier]()

    private var _willUpdate = [RepositorySpecifier]()
    private var _didUpdate = [RepositorySpecifier]()

    private var fetchedLock = Lock() 

    var willFetch: [RepositorySpecifier] {
        return fetchedLock.withLock({ _willFetch })
    }

    var didFetch: [RepositorySpecifier] {
        return fetchedLock.withLock({ _didFetch })
    }

    var willUpdate: [RepositorySpecifier] {
        return fetchedLock.withLock({ _willUpdate })
    }

    var didUpdate: [RepositorySpecifier] {
        return fetchedLock.withLock({ _didUpdate })
    }

    func fetchingWillBegin(handle: RepositoryManager.RepositoryHandle) {
        fetchedLock.withLock {
            _willFetch += [handle.repository]
        }
    }

    func fetchingDidFinish(handle: RepositoryManager.RepositoryHandle, error: Swift.Error?) {
        fetchedLock.withLock {
            _didFetch += [handle.repository]
        }
    }

    func handleWillUpdate(handle: RepositoryManager.RepositoryHandle) {
        fetchedLock.withLock {
            _willUpdate += [handle.repository]
        }
    }

    func handleDidUpdate(handle: RepositoryManager.RepositoryHandle) {
        fetchedLock.withLock {
            _didUpdate += [handle.repository]
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

            var prevHandle: RepositoryManager.RepositoryHandle?
            manager.lookup(repository: dummyRepo) { result in
                guard case .success(let handle) = result else {
                    XCTFail("Could not get handle")
                    return
                }

                prevHandle = handle
                XCTAssertEqual(provider.numFetches, 0)
            
                // Open the repository.
                let repository = try! handle.open()
                XCTAssertEqual(repository.tags, ["1.0.0"])

                // Create a checkout of the repository.
                let checkoutPath = path.appending(component: "checkout")
                try! handle.cloneCheckout(to: checkoutPath, editable: false)
            
                XCTAssert(localFileSystem.exists(checkoutPath.appending(component: "README.txt")))
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

            // We shouldn't have made any update call yet.
            XCTAssert(delegate.willUpdate.isEmpty)
            XCTAssert(delegate.didUpdate.isEmpty)

            // We should always get back the same handle once fetched.
            XCTNonNil(prevHandle) {
                try XCTAssert($0 === manager.lookupSynchronously(repository: dummyRepo))
            }
            // Since we looked up this repo again, we should have made a fetch call.
            XCTAssertEqual(provider.numFetches, 1)
            XCTAssertEqual(delegate.willUpdate, [dummyRepo])
            XCTAssertEqual(delegate.didUpdate, [dummyRepo])

            // Remove the repo.
            try manager.remove(repository: dummyRepo)
            // We should get a new handle now because we deleted the exisiting repository.
            XCTNonNil(prevHandle) {
                try XCTAssert($0 !== manager.lookupSynchronously(repository: dummyRepo))
            }
            
            // We should have tried fetching these two.
            XCTAssertEqual(Set(delegate.willFetch), [dummyRepo, badDummyRepo])
            XCTAssertEqual(Set(delegate.didFetch), [dummyRepo, badDummyRepo])
        }
    }

    func testReset() throws {
        mktmpdir { path in
            let repos = path.appending(component: "repo")
            let provider = DummyRepositoryProvider()
            let delegate = DummyRepositoryManagerDelegate()
            try localFileSystem.createDirectory(repos, recursive: true)
            let manager = RepositoryManager(path: repos, provider: provider, delegate: delegate)
            let dummyRepo = RepositorySpecifier(url: "dummy")
            _ = try manager.lookupSynchronously(repository: dummyRepo)
            _ = try manager.lookupSynchronously(repository: dummyRepo)
            XCTAssertEqual(delegate.willFetch.count, 1)
            XCTAssertEqual(delegate.didFetch.count, 1)
            manager.reset()
            XCTAssertTrue(!isDirectory(repos))
            try localFileSystem.createDirectory(repos, recursive: true)
            _ = try manager.lookupSynchronously(repository: dummyRepo)
            XCTAssertEqual(delegate.willFetch.count, 2)
            XCTAssertEqual(delegate.didFetch.count, 2)
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

                XCTAssertEqual(delegate.willFetch, [dummyRepo])
                XCTAssertEqual(delegate.didFetch, [dummyRepo])
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
                XCTAssertEqual(delegate.willFetch, [])
            }
            // We shouldn't have done a new fetch.
            XCTAssertEqual(provider.numClones, 1)
            XCTAssertEqual(provider.numFetches, 1)

            // Manually destroy the manager state, and check it still works.
            do {
                let delegate = DummyRepositoryManagerDelegate()
                var manager = RepositoryManager(path: path, provider: provider, delegate: delegate)
                try! removeFileTree(path.appending(component: "checkouts-state.json"))
                manager = RepositoryManager(path: path, provider: provider, delegate: delegate)
                let dummyRepo = RepositorySpecifier(url: "dummy")

                _ = try manager.lookupSynchronously(repository: dummyRepo)

                XCTAssertEqual(delegate.willFetch, [dummyRepo])
                XCTAssertEqual(delegate.didFetch, [dummyRepo])
            }
            // We should have re-fetched.
            XCTAssertEqual(provider.numClones, 2)
            XCTAssertEqual(provider.numFetches, 1)
        }
    }

    func testParallelLookups() throws {
        mktmpdir { path in
            let provider = DummyRepositoryProvider()
            let delegate = DummyRepositoryManagerDelegate()
            let manager = RepositoryManager(path: path, provider: provider, delegate: delegate)
            let dummyRepo = RepositorySpecifier(url: "dummy")
            // Condition to check if we have finished all lookups.
            let doneCondition = Condition()
            var done = false
            var set = Set<Int>()
            let numLookups = 1000

            for i in 0..<numLookups {
                manager.lookup(repository: dummyRepo) { _ in
                 doneCondition.whileLocked {
                        set.insert(i)
                        if set.count == numLookups {
                            // If set has all the lookups, we're done.
                            done = true
                            doneCondition.signal()
                        }
                    }
                }
            }
            // Block until all the lookups are done.
            doneCondition.whileLocked {
                while !done {
                    doneCondition.wait()
                }
            }
        }
    }

    func testSkipUpdate() throws {
        mktmpdir { path in
            let repos = path.appending(component: "repo")
            let provider = DummyRepositoryProvider()
            let delegate = DummyRepositoryManagerDelegate()
            try localFileSystem.createDirectory(repos, recursive: true)

            let manager = RepositoryManager(path: repos, provider: provider, delegate: delegate)
            let dummyRepo = RepositorySpecifier(url: "dummy")

            _ = try await { manager.lookup(repository: dummyRepo, completion: $0) }
            XCTAssertEqual(delegate.willFetch.count, 1)
            XCTAssertEqual(delegate.didFetch.count, 1)
            XCTAssertEqual(delegate.willUpdate.count, 0)
            XCTAssertEqual(delegate.didUpdate.count, 0)

            _ = try await { manager.lookup(repository: dummyRepo, completion: $0) }
            _ = try await { manager.lookup(repository: dummyRepo, completion: $0) }
            XCTAssertEqual(delegate.willFetch.count, 1)
            XCTAssertEqual(delegate.didFetch.count, 1)
            XCTAssertEqual(delegate.willUpdate.count, 2)
            XCTAssertEqual(delegate.didUpdate.count, 2)

            _ = try await { manager.lookup(repository: dummyRepo, skipUpdate: true, completion: $0) }
            XCTAssertEqual(delegate.willFetch.count, 1)
            XCTAssertEqual(delegate.didFetch.count, 1)
            XCTAssertEqual(delegate.willUpdate.count, 2)
            XCTAssertEqual(delegate.didUpdate.count, 2)
        }
    }

    static var allTests = [
        ("testBasics", testBasics),
        ("testParallelLookups", testParallelLookups),
        ("testPersistence", testPersistence),
        ("testReset", testReset),
        ("testSkipUpdate", testSkipUpdate),
    ]
}
