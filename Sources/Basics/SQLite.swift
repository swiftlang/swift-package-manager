//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import TSCBasic
import Foundation

#if SWIFT_PACKAGE && (os(Windows) || os(Android))
#if USE_IMPL_ONLY_IMPORTS
@_implementationOnly import SwiftToolchainCSQLite
#else
import SwiftToolchainCSQLite
#endif
#else
#if USE_IMPL_ONLY_IMPORTS
@_implementationOnly import SPMSQLite3
#else
import SPMSQLite3
#endif
#endif

/// A minimal SQLite wrapper.
package final class SQLite {
    /// The location of the database.
    package let location: Location

    /// The configuration for the database.
    package let configuration: Configuration

    /// Pointer to the database.
    let db: OpaquePointer

    /// Create or open the database at the given path.
    ///
    /// The database is opened in serialized mode.
    package init(location: Location, configuration: Configuration = Configuration()) throws {
        self.location = location
        self.configuration = configuration

        var handle: OpaquePointer?
        try Self.checkError(
            {
                sqlite3_open_v2(
                    location.pathString,
                    &handle,
                    SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                    nil
                )
            },
            description: "Unable to open database at \(self.location)"
        )

        guard let db = handle else {
            throw StringError("Unable to open database at \(self.location)")
        }
        self.db = db
        try Self.checkError({ sqlite3_extended_result_codes(db, 1) }, description: "Unable to configure database")
        try Self.checkError(
            { sqlite3_busy_timeout(db, self.configuration.busyTimeoutMilliseconds) },
            description: "Unable to configure database busy timeout"
        )
        if let maxPageCount = self.configuration.maxPageCount {
            try self.exec(query: "PRAGMA max_page_count=\(maxPageCount);")
        }
    }

    @available(*, deprecated, message: "use init(location:configuration) instead")
    package convenience init(dbPath: AbsolutePath) throws {
        try self.init(location: .path(dbPath))
    }

    /// Prepare the given query.
    package func prepare(query: String) throws -> PreparedStatement {
        try PreparedStatement(db: self.db, query: query)
    }

    /// Directly execute the given query.
    ///
    /// Note: Use withCString for string arguments.
    package func exec(query queryString: String, args: [CVarArg] = [], _ callback: SQLiteExecCallback? = nil) throws {
        let query = withVaList(args) { ptr in
            sqlite3_vmprintf(queryString, ptr)
        }

        let wcb = callback.map { CallbackWrapper($0) }
        let callbackCtx = wcb.map { Unmanaged.passUnretained($0).toOpaque() }

        var err: UnsafeMutablePointer<Int8>?
        try Self.checkError { sqlite3_exec(db, query, sqlite_callback, callbackCtx, &err) }

        sqlite3_free(query)

        if let err {
            let errorString = String(cString: err)
            sqlite3_free(err)
            throw StringError(errorString)
        }
    }

    package func close() throws {
        try Self.checkError { sqlite3_close(db) }
    }

    package typealias SQLiteExecCallback = ([Column]) -> Void

    package struct Configuration {
        package var busyTimeoutMilliseconds: Int32
        package var maxSizeInBytes: Int?

        // https://www.sqlite.org/pgszchng2016.html
        private let defaultPageSizeInBytes = 1024

        package init() {
            self.busyTimeoutMilliseconds = 5000
            self.maxSizeInBytes = .none
        }

        // FIXME: deprecated 12/2020, remove once clients migrated over
        @available(*, deprecated, message: "use busyTimeout instead")
        package var busyTimeoutSeconds: Int32 {
            get {
                self._busyTimeoutSeconds
            } set {
                self._busyTimeoutSeconds = newValue
            }
        }

        // so tests dont warn
        internal var _busyTimeoutSeconds: Int32 {
            get {
                Int32(truncatingIfNeeded: Int(Double(self.busyTimeoutMilliseconds) / 1000))
            } set {
                self.busyTimeoutMilliseconds = newValue * 1000
            }
        }

        package var maxSizeInMegabytes: Int? {
            get {
                self.maxSizeInBytes.map { $0 / (1024 * 1024) }
            }
            set {
                self.maxSizeInBytes = newValue.map { $0 * 1024 * 1024 }
            }
        }

        package var maxPageCount: Int? {
            self.maxSizeInBytes.map { $0 / self.defaultPageSizeInBytes }
        }
    }

    package enum Location: Sendable {
        case path(AbsolutePath)
        case memory
        case temporary

        var pathString: String {
            switch self {
            case .path(let path):
                return path.pathString
            case .memory:
                return ":memory:"
            case .temporary:
                return ""
            }
        }
    }

    /// Represents an sqlite value.
    package enum SQLiteValue {
        case null
        case string(String)
        case int(Int)
        case blob(Data)
    }

    /// Represents a row returned by called step() on a prepared statement.
    package struct Row {
        /// The pointer to the prepared statement.
        let stmt: OpaquePointer

        /// Get integer at the given column index.
        package func int(at index: Int32) -> Int {
            Int(sqlite3_column_int64(self.stmt, index))
        }

        /// Get blob data at the given column index.
        package func blob(at index: Int32) -> Data {
            let bytes = sqlite3_column_blob(stmt, index)!
            let count = sqlite3_column_bytes(stmt, index)
            return Data(bytes: bytes, count: Int(count))
        }

        /// Get string at the given column index.
        package func string(at index: Int32) -> String {
            String(cString: sqlite3_column_text(self.stmt, index))
        }
    }

    package struct Column {
        package var name: String
        package var value: String
    }

    /// Represents a prepared statement.
    package struct PreparedStatement {
        typealias sqlite3_destructor_type = @convention(c) (UnsafeMutableRawPointer?) -> Void
        static let SQLITE_STATIC = unsafeBitCast(0, to: sqlite3_destructor_type.self)
        static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        /// The pointer to the prepared statement.
        let stmt: OpaquePointer

        package init(db: OpaquePointer, query: String) throws {
            var stmt: OpaquePointer?
            try SQLite.checkError { sqlite3_prepare_v2(db, query, -1, &stmt, nil) }
            self.stmt = stmt!
        }

        /// Evaluate the prepared statement.
        @discardableResult
        package func step() throws -> Row? {
            let result = sqlite3_step(stmt)

            switch result {
            case SQLITE_DONE:
                return nil
            case SQLITE_ROW:
                return Row(stmt: self.stmt)
            default:
                throw StringError(String(cString: sqlite3_errstr(result)))
            }
        }

        /// Bind the given arguments to the statement.
        package func bind(_ arguments: [SQLiteValue]) throws {
            for (idx, argument) in arguments.enumerated() {
                let idx = Int32(idx) + 1
                switch argument {
                case .null:
                    try checkError { sqlite3_bind_null(stmt, idx) }
                case .int(let int):
                    try checkError { sqlite3_bind_int64(stmt, idx, Int64(int)) }
                case .string(let str):
                    try checkError { sqlite3_bind_text(stmt, idx, str, -1, Self.SQLITE_TRANSIENT) }
                case .blob(let blob):
                    try checkError {
                        blob.withUnsafeBytes { ptr in
                            sqlite3_bind_blob(
                                stmt,
                                idx,
                                ptr.baseAddress,
                                Int32(blob.count),
                                Self.SQLITE_TRANSIENT
                            )
                        }
                    }
                }
            }
        }

        /// Reset the prepared statement.
        package func reset() throws {
            try SQLite.checkError { sqlite3_reset(stmt) }
        }

        /// Clear bindings from the prepared statement.
        package func clearBindings() throws {
            try SQLite.checkError { sqlite3_clear_bindings(stmt) }
        }

        /// Finalize the statement and free up resources.
        package func finalize() throws {
            try SQLite.checkError { sqlite3_finalize(stmt) }
        }
    }

    fileprivate class CallbackWrapper {
        var callback: SQLiteExecCallback
        init(_ callback: @escaping SQLiteExecCallback) {
            self.callback = callback
        }
    }

    private static func checkError(_ fn: () -> Int32, description prefix: String? = .none) throws {
        let result = fn()
        if result != SQLITE_OK {
            var description = String(cString: sqlite3_errstr(result))
            switch description.lowercased() {
            case "database or disk is full":
                throw Errors.databaseFull
            default:
                if let prefix {
                    description = "\(prefix): \(description)"
                }
                throw StringError(description)
            }
        }
    }

    package enum Errors: Error {
        case databaseFull
    }
}

// Explicitly mark this class as non-Sendable
@available(*, unavailable)
extension SQLite: Sendable {}

private func sqlite_callback(
    _ ctx: UnsafeMutableRawPointer?,
    _ numColumns: Int32,
    _ columns: UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>?,
    _ columnNames: UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>?
) -> Int32 {
    guard let ctx else { return 0 }
    guard let columnNames, let columns else { return 0 }
    let numColumns = Int(numColumns)
    var result: [SQLite.Column] = []

    for idx in 0 ..< numColumns {
        var name = ""
        if let ptr = columnNames.advanced(by: idx).pointee {
            name = String(cString: ptr)
        }
        var value = ""
        if let ptr = columns.advanced(by: idx).pointee {
            value = String(cString: ptr)
        }
        result.append(SQLite.Column(name: name, value: value))
    }

    let wcb = Unmanaged<SQLite.CallbackWrapper>.fromOpaque(ctx).takeUnretainedValue()
    wcb.callback(result)

    return 0
}
