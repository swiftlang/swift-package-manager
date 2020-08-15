/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import Foundation

/// A protocol for Data -> Data cache.
public protocol PersistentCacheProtocol {
    func get(key: Data) throws -> Data?
    func put(key: Data, value: Data) throws
}

/// SQLite backed persistent cache.
public final class SQLiteBackedPersistentCache: PersistentCacheProtocol {
    let db: SQLite

    init(db: SQLite) throws {
        self.db = db
        
        let table = """
                CREATE TABLE IF NOT EXISTS TSCCACHE (
                    key BLOB PRIMARY KEY NOT NULL,
                    value BLOB NOT NULL
                );
            """

        try db.exec(query: table)
        try db.exec(query: "PRAGMA journal_mode=WAL;")
    }

    deinit {
        try? db.close()
    }

    public convenience init(cacheFilePath: AbsolutePath) throws {
        let db = try SQLite(dbPath: cacheFilePath)
        try self.init(db: db)
    }

    public func get(key: Data) throws -> Data? {
        let readStmt = try self.db.prepare(query: "SELECT value FROM TSCCACHE WHERE key == ? LIMIT 1;")
        try readStmt.bind([.blob(key)])
        let row = try readStmt.step()
        let blob = row?.blob(at: 0)
        try readStmt.finalize()
        return blob
    }

    public func put(key: Data, value: Data) throws {
        let writeStmt = try self.db.prepare(query: "INSERT OR IGNORE INTO TSCCACHE VALUES (?, ?)")
        let bindings: [SQLite.SQLiteValue] = [
            .blob(key),
            .blob(value),
        ]
        try writeStmt.bind(bindings)
        try writeStmt.step()
        try writeStmt.finalize()
    }
}
