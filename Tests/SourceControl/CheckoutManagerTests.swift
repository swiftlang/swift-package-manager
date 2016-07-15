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

private enum DummyError: Swift.Error {
    case invalidRepository
}

private class DummyRepositoryProvider: RepositoryProvider {
    var numFetches = 0
    
    func fetch(repository: RepositorySpecifier, to path: AbsolutePath) throws {
        numFetches += 1
        
        // We only support one dummy URL.
        if repository.url.basename != "dummy" {
            throw DummyError.invalidRepository
        }
    }

    func open(repository: RepositorySpecifier, at path: AbsolutePath) -> Repository {
        fatalError("unexpected API call")
    }
}

class CheckoutManagerTests: XCTestCase {
    func testBasics() {
        mktmpdir { path in
            let manager = CheckoutManager(path: path, provider: DummyRepositoryProvider())

            // Check that we can "fetch" a repository.
            let dummyRepo = RepositorySpecifier(url: "dummy")
            let handle = manager.lookup(repository: dummyRepo)

            // We should always get back the same handle once fetched.
            XCTAssert(handle === manager.lookup(repository: dummyRepo))
            
            // Validate that the repo is available.
            XCTAssertTrue(handle.isAvailable)

            // Get a bad repository.
            let badDummyRepo = RepositorySpecifier(url: "badDummy")
            let badHandle = manager.lookup(repository: badDummyRepo)

            // Validate that the repo is unavailable.
            XCTAssertFalse(badHandle.isAvailable)
        }
    }

    /// Check the behavior of the observer of repository status.
    func testObserver() {
        mktmpdir { path in
            let manager = CheckoutManager(path: path, provider: DummyRepositoryProvider())
            let dummyRepo = RepositorySpecifier(url: "dummy")
            let handle = manager.lookup(repository: dummyRepo)

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
                let manager = CheckoutManager(path: path, provider: provider)
                let dummyRepo = RepositorySpecifier(url: "dummy")
                let handle = manager.lookup(repository: dummyRepo)
                // FIXME: Wait for repo to become available.
                XCTAssertTrue(handle.isAvailable)
            }
            // We should have performed one fetch.
            XCTAssertEqual(provider.numFetches, 1)

            // Create a new manager, and fetch.
            do {
                let manager = CheckoutManager(path: path, provider: provider)
                let dummyRepo = RepositorySpecifier(url: "dummy")
                let handle = manager.lookup(repository: dummyRepo)
                // FIXME: Wait for repo to become available.
                XCTAssertTrue(handle.isAvailable)
            }
            // We shouldn't have done a new fetch.
            XCTAssertEqual(provider.numFetches, 1)
        }
    }

    static var allTests = [
        ("testBasic", testBasics),
        ("testObserver", testObserver),
        ("testPersistence", testPersistence),
    ]
}
