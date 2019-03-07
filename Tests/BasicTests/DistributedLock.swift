/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic

class DistributedLockTests: XCTestCase {
    func testBasics() throws {
        let tempDir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let lockPath = tempDir.path.appending(component: "lock")
        guard let lock = Basic._DistributedLock(path: lockPath.pathString) else {
          return XCTFail("Failed to instantiate a lock")
        }

        XCTAssertTrue(lock.try())
        XCTAssertTrue(FileManager.default.fileExists(atPath: lockPath.pathString))
        XCTAssertFalse(lock.try())
        lock.unlock()
        XCTAssertFalse(FileManager.default.fileExists(atPath: lockPath.pathString))
        XCTAssertTrue(lock.try())
    }
}
