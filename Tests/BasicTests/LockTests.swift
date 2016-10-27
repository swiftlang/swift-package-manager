/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import Dispatch

import Basic
import POSIX
import TestSupport

class LockTests: XCTestCase {
    func testBasics() {
        // FIXME: Make this a more interesting test once we have concurrency primitives.
        var lock = Basic.Lock()
        var count = 0
        let N = 100
        for _ in 0..<N {
            lock.withLock {
                count += 1
            }
        }
        XCTAssertEqual(count, N)
    }

    func testFileLock() throws {
        // Shared resource file.
        let sharedResource = try TemporaryFile()
        // Directory where lock file should be created.
        let tempDir = try TemporaryDirectory()

        // Run the same executable multiple times and
        // we can expect the final result to be sum of the
        // contents we write in the shared file.
        let N = 10
        let threads = (1...N).map { idx in
            return Thread {
                _ = try! SwiftPMProduct.TestSupportExecutable.execute(["fileLockTest", tempDir.path.asString, sharedResource.path.asString, String(idx)])
            }
        }
        threads.forEach { $0.start() }
        threads.forEach { $0.join() }

        XCTAssertEqual(try localFileSystem.readFileContents(sharedResource.path).asString, String((N * (N + 1) / 2 )))
    }

    func testFileLockTimeout() throws {
        let tempDir = try TemporaryDirectory()
        let lock = FileLock(name: "TestLock", cachePath: tempDir.path)
        // Get a lock.
        let locked = try lock.lock()
        XCTAssertTrue(locked)
        // Try to get the lock again with a timeout.
        let relocked = try lock.lock(timeout: 0.01)
        XCTAssertFalse(relocked)
        lock.unlock()
    }

    static var allTests = [
        ("testBasics", testBasics),
        ("testFileLock", testFileLock),
    ]
}
