/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import TestSupport

class LockTests: XCTestCase {
    func testBasics() {
        // FIXME: Make this a more interesting test once we have concurrency primitives.
        let lock = Basic.Lock()
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
        let tempDir = try TemporaryDirectory(removeTreeOnDeinit: true)

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

    static var allTests = [
        ("testBasics", testBasics),
        ("testFileLock", testFileLock),
    ]
}
