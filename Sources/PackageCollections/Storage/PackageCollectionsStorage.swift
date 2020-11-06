/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import Dispatch
import struct Foundation.Data
import class Foundation.JSONDecoder
import class Foundation.JSONEncoder
import struct Foundation.URL
import TSCBasic
import TSCUtility

// MARK: - PackageCollectionsStorage

public protocol PackageCollectionsStorage {
    /// Writes `PackageCollection` to storage.
    ///
    /// - Parameters:
    ///   - collection: The `PackageCollection`
    ///   - callback: The closure to invoke when result becomes available
    func put(collection: PackageCollectionsModel.Collection,
             callback: @escaping (Result<PackageCollectionsModel.Collection, Error>) -> Void)

    /// Removes `PackageCollection` from storage.
    ///
    /// - Parameters:
    ///   - identifier: The identifier of the `PackageCollection`
    ///   - callback: The closure to invoke when result becomes available
    func remove(identifier: PackageCollectionsModel.CollectionIdentifier,
                callback: @escaping (Result<Void, Error>) -> Void)

    /// Returns `PackageCollection` for the given identifier.
    ///
    /// - Parameters:
    ///   - identifier: The identifier of the `PackageCollection`
    ///   - callback: The closure to invoke when result becomes available
    func get(identifier: PackageCollectionsModel.CollectionIdentifier,
             callback: @escaping (Result<PackageCollectionsModel.Collection, Error>) -> Void)

    /// Returns `PackageCollection`s for the given identifiers, or all if none specified.
    ///
    /// - Parameters:
    ///   - identifiers: Optional. The identifiers of the `PackageCollection`
    ///   - callback: The closure to invoke when result becomes available
    func list(identifiers: [PackageCollectionsModel.CollectionIdentifier]?,
              callback: @escaping (Result<[PackageCollectionsModel.Collection], Error>) -> Void)

    /// Returns `PackageSearchResult` for the given search criteria.
    ///
    /// - Parameters:
    ///   - identifiers: Optional. The identifiers of the `PackageCollection`s
    ///   - query: The search query expression
    ///   - callback: The closure to invoke when result becomes available
    func searchPackages(identifiers: [PackageCollectionsModel.CollectionIdentifier]?,
                        query: String,
                        callback: @escaping (Result<PackageCollectionsModel.PackageSearchResult, Error>) -> Void)

    /// Returns `TargetSearchResult` for the given search criteria.
    ///
    /// - Parameters:
    ///   - identifiers: Optional. The identifiers of the `PackageCollection`
    ///   - query: The search query expression
    ///   - type: The search type
    ///   - callback: The closure to invoke when result becomes available
    func searchTargets(identifiers: [PackageCollectionsModel.CollectionIdentifier]?,
                       query: String,
                       type: PackageCollectionsModel.TargetSearchType,
                       callback: @escaping (Result<PackageCollectionsModel.TargetSearchResult, Error>) -> Void)
}

// MARK: - SQLitePackageCollectionsStorage

final class SQLitePackageCollectionsStorage: PackageCollectionsStorage, Closable {
    static let batchSize = 100

    let fileSystem: FileSystem
    let location: SQLite.Location

    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder

    // for concurrent for DB access
    private let queue = DispatchQueue(label: "org.swift.swiftpm.SQLitePackageCollectionsStorage", attributes: .concurrent)

    private var state = State.idle
    private let stateLock = Lock()

    init(location: SQLite.Location? = nil) {
        self.location = location ?? .path(localFileSystem.swiftPMCacheDirectory.appending(components: "package-collection.db"))
        switch self.location {
        case .path, .temporary:
            self.fileSystem = localFileSystem
        case .memory:
            self.fileSystem = InMemoryFileSystem()
        }
        self.jsonEncoder = JSONEncoder()
        self.jsonDecoder = JSONDecoder()
    }

    convenience init(path: AbsolutePath) {
        self.init(location: .path(path))
    }

    deinit {
        guard case .disconnected = (self.stateLock.withLock { self.state }) else {
            return assertionFailure("db should be closed")
        }
    }

    func close() throws {
        try self.stateLock.withLock {
            if case .connected(let db) = self.state {
                try db.close()
            }
            self.state = .disconnected
        }
    }

    func put(collection: PackageCollectionsModel.Collection,
             callback: @escaping (Result<PackageCollectionsModel.Collection, Error>) -> Void) {
        self.queue.async {
            do {
                let query = "INSERT OR IGNORE INTO PACKAGES_COLLECTIONS VALUES (?, ?);"
                try self.executeStatement(query) { statement -> Void in
                    let data = try self.jsonEncoder.encode(collection)

                    let bindings: [SQLite.SQLiteValue] = [
                        .string(collection.identifier.databaseKey()),
                        .blob(data),
                    ]
                    try statement.bind(bindings)
                    try statement.step()
                }
                callback(.success(collection))
            } catch {
                callback(.failure(error))
            }
        }
    }

    func remove(identifier: PackageCollectionsModel.CollectionIdentifier,
                callback: @escaping (Result<Void, Error>) -> Void) {
        self.queue.async {
            do {
                let query = "DELETE FROM PACKAGES_COLLECTIONS WHERE key == ?;"
                try self.executeStatement(query) { statement -> Void in
                    let bindings: [SQLite.SQLiteValue] = [
                        .string(identifier.databaseKey()),
                    ]
                    try statement.bind(bindings)
                    try statement.step()
                }
                callback(.success(()))
            } catch {
                callback(.failure(error))
            }
        }
    }

    func get(identifier: PackageCollectionsModel.CollectionIdentifier,
             callback: @escaping (Result<PackageCollectionsModel.Collection, Error>) -> Void) {
        self.queue.async {
            do {
                let query = "SELECT value FROM PACKAGES_COLLECTIONS WHERE key == ? LIMIT 1;"
                let collection = try self.executeStatement(query) { statement -> PackageCollectionsModel.Collection in
                    try statement.bind([.string(identifier.databaseKey())])

                    let row = try statement.step()
                    guard let data = row?.blob(at: 0) else {
                        throw NotFoundError("\(identifier)")
                    }

                    let collection = try self.jsonDecoder.decode(PackageCollectionsModel.Collection.self, from: data)
                    return collection
                }
                callback(.success(collection))
            } catch {
                callback(.failure(error))
            }
        }
    }

    func list(identifiers: [PackageCollectionsModel.CollectionIdentifier]? = nil,
              callback: @escaping (Result<[PackageCollectionsModel.Collection], Error>) -> Void) {
        self.queue.async {
            do {
                var blobs = [Data]()
                if let identifiers = identifiers {
                    // TODO: consider running these in parallel
                    var index = 0
                    while index < identifiers.count {
                        let slice = identifiers[index ..< min(index + Self.batchSize, identifiers.count)]
                        let query = "SELECT value FROM PACKAGES_COLLECTIONS WHERE key in (\(slice.map { _ in "?" }.joined(separator: ",")));"
                        try self.executeStatement(query) { statement in
                            try statement.bind(slice.compactMap { .string($0.databaseKey()) })
                            while let row = try statement.step() {
                                blobs.append(row.blob(at: 0))
                            }
                        }
                        index += Self.batchSize
                    }
                } else {
                    let query = "SELECT value FROM PACKAGES_COLLECTIONS;"
                    try self.executeStatement(query) { statement in
                        while let row = try statement.step() {
                            blobs.append(row.blob(at: 0))
                        }
                    }
                }

                // TODO: consider some diagnostics / warning for invalid data
                let collections = blobs.compactMap { data -> PackageCollectionsModel.Collection? in
                    try? self.jsonDecoder.decode(PackageCollectionsModel.Collection.self, from: data)
                }
                callback(.success(collections))
            } catch {
                callback(.failure(error))
            }
        }
    }

    // FIXME: implement this
    func searchPackages(identifiers: [PackageCollectionsModel.CollectionIdentifier]? = nil,
                        query: String,
                        callback: @escaping (Result<PackageCollectionsModel.PackageSearchResult, Error>) -> Void) {
        fatalError("not implemented")
    }

    // FIXME: implement this
    func searchTargets(identifiers: [PackageCollectionsModel.CollectionIdentifier]? = nil,
                       query: String,
                       type: PackageCollectionsModel.TargetSearchType,
                       callback: @escaping (Result<PackageCollectionsModel.TargetSearchResult, Error>) -> Void) {
        fatalError("not implemented")
    }

    private func createSchemaIfNecessary(db: SQLite) throws {
        let table = """
            CREATE TABLE IF NOT EXISTS PACKAGES_COLLECTIONS (
                key STRING PRIMARY KEY NOT NULL,
                value BLOB NOT NULL
            );
        """

        try db.exec(query: table)
        try db.exec(query: "PRAGMA journal_mode=WAL;")
    }

    private enum State {
        case idle
        case connected(SQLite)
        case disconnected
        case error
    }

    private func executeStatement<T>(_ query: String, _ body: (SQLite.PreparedStatement) throws -> T) throws -> T {
        try self.withDB { db in
            let result: Result<T, Error>
            let statement = try db.prepare(query: query)
            do {
                result = .success(try body(statement))
            } catch {
                result = .failure(error)
            }
            try statement.finalize()
            switch result {
            case .failure(let error):
                throw error
            case .success(let value):
                return value
            }
        }
    }

    private func withDB<T>(_ body: (SQLite) throws -> T) throws -> T {
        let createDB = { () throws -> SQLite in
            let db = try SQLite(location: self.location)
            try self.createSchemaIfNecessary(db: db)
            return db
        }

        let db = try stateLock.withLock { () -> SQLite in
            let db: SQLite
            switch (self.location, self.state) {
            case (.path(let path), .connected(let database)):
                if self.fileSystem.exists(path) {
                    db = database
                } else {
                    try database.close()
                    try self.fileSystem.createDirectory(path.parentDirectory, recursive: true)
                    db = try createDB()
                }
            case (.path(let path), _):
                if !self.fileSystem.exists(path) {
                    try self.fileSystem.createDirectory(path.parentDirectory, recursive: true)
                }
                db = try createDB()
            case (_, .connected(let database)):
                db = database
            case (_, _):
                db = try createDB()
            }
            self.state = .connected(db)
            return db
        }

        return try body(db)
    }
}

// MARK: - Utility

private extension PackageCollectionsModel.Collection.Identifier {
    func databaseKey() -> String {
        switch self {
        case .feed(let url):
            return url.absoluteString
        }
    }
}
