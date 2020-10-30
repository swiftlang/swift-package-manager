/*
 This source file is part of the Swift.org open source project

 Copyright 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import TSCBasic
import TSCTestSupport
import TSCUtility
import XCTest

class SQLiteTests: XCTestCase {
    func testFile() throws {
        try testWithTemporaryDirectory { tmpdir in
            let path = tmpdir.appending(component: "test.db")
            let db = try SQLite(location: .path(path))
            defer { XCTAssertNoThrow(try db.close()) }

            try validateDB(db: db)

            XCTAssertTrue(localFileSystem.exists(path), "expected file to be written")
        }
    }

    func testTemp() throws {
        let db = try SQLite(location: .temporary)
        defer { XCTAssertNoThrow(try db.close()) }

        try self.validateDB(db: db)
    }

    func testMemory() throws {
        let db = try SQLite(location: .memory)
        defer { XCTAssertNoThrow(try db.close()) }

        try self.validateDB(db: db)
    }

    func validateDB(db: SQLite, file: StaticString = #file, line: UInt = #line) throws {
        let tableName = UUID().uuidString
        let count = Int.random(in: 50 ... 100)

        try db.exec(query: "CREATE TABLE \"\(tableName)\" (ID INT PRIMARY KEY, NAME STRING);")

        for index in 0 ..< count {
            let statement = try db.prepare(query: "INSERT INTO \"\(tableName)\" VALUES (?, ?);")
            defer { XCTAssertNoThrow(try statement.finalize(), file: file, line: line) }
            try statement.bind([.int(index), .string(UUID().uuidString)])
            try statement.step()
        }

        do {
            let statement = try db.prepare(query: "SELECT * FROM \"\(tableName)\";")
            defer { XCTAssertNoThrow(try statement.finalize(), file: file, line: line) }
            var results = [SQLite.Row]()
            while let row = try statement.step() {
                results.append(row)
            }
            XCTAssertEqual(results.count, count, "expected results count to match", file: file, line: line)
        }

        do {
            let statement = try db.prepare(query: "SELECT * FROM \"\(tableName)\" where ID = ?;")
            defer { XCTAssertNoThrow(try statement.finalize(), file: file, line: line) }
            try statement.bind([.int(Int.random(in: 0 ..< count))])
            let row = try statement.step()
            XCTAssertNotNil(row, "expected results")
        }
    }
}
