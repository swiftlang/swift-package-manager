//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Dispatch

@testable import Basics
import Testing

struct SQLiteTests {
    @Test(.tags(Tag.TestSize.small))
    func preparingAfterCloseThrows() throws {
        let db = try SQLite(location: .memory)
        try db.close()

        #expect(throws: StringError("database is closed")) {
            try db.prepare(query: "SELECT id FROM test;")
        }
    }

    @Test(.tags(Tag.TestSize.small))
    func executingAfterCloseThrows() throws {
        let db = try SQLite(location: .memory)
        try db.close()

        #expect(throws: StringError("database is closed")) {
            try db.exec(query: "SELECT id FROM test;")
        }
    }

    @Test(.tags(Tag.TestSize.small))
    func closingMoreThanOnceSucceeds() throws {
        let db = try SQLite(location: .memory)
        try db.close()
        try db.close()
    }

    @Test(.tags(Tag.TestSize.small))
    func closingWithAliveStatementFailsAndLeavesDatabaseUsable() throws {
        let db = try SQLite(location: .memory)
        try db.exec(query: "CREATE TABLE test (id INTEGER);")
        let statement = try db.prepare(query: "SELECT id FROM test;")

        #expect(throws: (any Error).self) {
            try db.close()
        }

        try statement.finalize()
        try db.close()
    }

    @Test(.tags(Tag.TestSize.small))
    func preparingConcurrentlyWithCloseDoesNotUseFreedHandle() throws {
        for _ in 0 ..< 50 {
            let db = try SQLite(location: .memory)
            try db.exec(query: "CREATE TABLE test (id INTEGER);")

            let group = DispatchGroup()
            for _ in 0 ..< 4 {
                DispatchQueue.sharedConcurrent.async(group: group) {
                    for _ in 0 ..< 25 {
                        // Both outcomes are valid: the statement is prepared on a live
                        // connection, or preparing fails because the connection is closed.
                        guard let statement = try? db.prepare(query: "SELECT id FROM test;") else {
                            continue
                        }
                        try? statement.finalize()
                    }
                }
            }
            DispatchQueue.sharedConcurrent.async(group: group) {
                try? db.close()
            }

            group.wait()
            try db.close()
        }
    }
}
