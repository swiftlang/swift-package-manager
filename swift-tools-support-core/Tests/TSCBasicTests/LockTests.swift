/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import TSCBasic
import TSCTestSupport

class LockTests: XCTestCase {
    func testBasics() {
        // FIXME: Make this a more interesting test once we have concurrency primitives.
        let lock = TSCBasic.Lock()
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
        try withTemporaryFile { sharedResource in
            // Directory where lock file should be created.
            try withTemporaryDirectory(removeTreeOnDeinit: true) { tempDirPath in
                // Run the same executable multiple times and
                // we can expect the final result to be sum of the
                // contents we write in the shared file.
                let N = 10
                let threads = (1...N).map { idx in
                    return Thread {
                        _ = try! TestSupportExecutable.execute(["fileLockTest", tempDirPath.pathString, sharedResource.path.pathString, String(idx)])
                    }
                }
                threads.forEach { $0.start() }
                threads.forEach { $0.join() }

                XCTAssertEqual(try localFileSystem.readFileContents(sharedResource.path).description, String((N * (N + 1) / 2 )))
            }
        }
    }

    func testReadWriteFileLock() throws {
        try withTemporaryDirectory { tempDir in
            let fileA = tempDir.appending(component: "fileA")
            let fileB = tempDir.appending(component: "fileB")

            let writerThreads = (0..<100).map { _ in
                return Thread {
                    let lock = FileLock(name: "foo", cachePath: tempDir)
                    try! lock.withLock(type: .exclusive) {
                        // Get thr current contents of the file if any.
                        let valueA: Int
                        if localFileSystem.exists(fileA) {
                            valueA = Int(try localFileSystem.readFileContents(fileA).description) ?? 0
                        } else {
                            valueA = 0
                        }
                        // Sum and write back to file.
                        try localFileSystem.writeFileContents(fileA, bytes: ByteString(encodingAsUTF8: String(valueA + 1)))

                        Thread.yield()

                        // Get thr current contents of the file if any.
                        let valueB: Int
                        if localFileSystem.exists(fileB) {
                            valueB = Int(try localFileSystem.readFileContents(fileB).description) ?? 0
                        } else {
                            valueB = 0
                        }
                        // Sum and write back to file.
                        try localFileSystem.writeFileContents(fileB, bytes: ByteString(encodingAsUTF8: String(valueB + 1)))
                    }
                }
            }

            let readerThreads = (0..<20).map { _ in
                return Thread {
                    let lock = FileLock(name: "foo", cachePath: tempDir)
                    try! lock.withLock(type: .shared) {
                        try XCTAssertEqual(localFileSystem.readFileContents(fileA), localFileSystem.readFileContents(fileB))

                        Thread.yield()

                        try XCTAssertEqual(localFileSystem.readFileContents(fileA), localFileSystem.readFileContents(fileB))
                    }
                }
            }

            writerThreads.forEach { $0.start() }
            readerThreads.forEach { $0.start() }
            writerThreads.forEach { $0.join() }
            readerThreads.forEach { $0.join() }

            try XCTAssertEqual(localFileSystem.readFileContents(fileA), "100")
            try XCTAssertEqual(localFileSystem.readFileContents(fileB), "100")
        }
    }

}
