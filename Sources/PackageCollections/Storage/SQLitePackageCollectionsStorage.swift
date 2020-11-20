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
import PackageModel
import TSCBasic
import TSCUtility

final class SQLitePackageCollectionsStorage: PackageCollectionsStorage, Closable {
    static let batchSize = 100

    let fileSystem: FileSystem
    let location: SQLite.Location

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    // for concurrent for DB access
    private let queue = DispatchQueue(label: "org.swift.swiftpm.SQLitePackageCollectionsStorage", attributes: .concurrent)

    private var state = State.idle
    private let stateLock = Lock()

    private var cache = [Model.CollectionIdentifier: Model.Collection]()
    private let cacheLock = Lock()

    init(location: SQLite.Location? = nil) {
        self.location = location ?? .path(localFileSystem.swiftPMCacheDirectory.appending(components: "package-collection.db"))
        switch self.location {
        case .path, .temporary:
            self.fileSystem = localFileSystem
        case .memory:
            self.fileSystem = InMemoryFileSystem()
        }
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
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

    func put(collection: Model.Collection,
             callback: @escaping (Result<Model.Collection, Error>) -> Void) {
        self.queue.async {
            do {
                // write to db
                let query = "INSERT OR REPLACE INTO PACKAGES_COLLECTIONS VALUES (?, ?);"
                try self.executeStatement(query) { statement -> Void in
                    let data = try self.encoder.encode(collection)

                    let bindings: [SQLite.SQLiteValue] = [
                        .string(collection.identifier.databaseKey()),
                        .blob(data),
                    ]
                    try statement.bind(bindings)
                    try statement.step()
                }
                // write to cache
                self.cacheLock.withLock {
                    self.cache[collection.identifier] = collection
                }
                callback(.success(collection))
            } catch {
                callback(.failure(error))
            }
        }
    }

    func remove(identifier: Model.CollectionIdentifier,
                callback: @escaping (Result<Void, Error>) -> Void) {
        self.queue.async {
            do {
                // write to db
                let query = "DELETE FROM PACKAGES_COLLECTIONS WHERE key == ?;"
                try self.executeStatement(query) { statement -> Void in
                    let bindings: [SQLite.SQLiteValue] = [
                        .string(identifier.databaseKey()),
                    ]
                    try statement.bind(bindings)
                    try statement.step()
                }
                // write to cache
                self.cacheLock.withLock {
                    self.cache[identifier] = nil
                }
                callback(.success(()))
            } catch {
                callback(.failure(error))
            }
        }
    }

    func get(identifier: Model.CollectionIdentifier,
             callback: @escaping (Result<Model.Collection, Error>) -> Void) {
        // try read to cache
        if let collection = (self.cacheLock.withLock { self.cache[identifier] }) {
            return callback(.success(collection))
        }

        // go to db if not found
        self.queue.async {
            do {
                let query = "SELECT value FROM PACKAGES_COLLECTIONS WHERE key == ? LIMIT 1;"
                let collection = try self.executeStatement(query) { statement -> Model.Collection in
                    try statement.bind([.string(identifier.databaseKey())])

                    let row = try statement.step()
                    guard let data = row?.blob(at: 0) else {
                        throw NotFoundError("\(identifier)")
                    }

                    let collection = try self.decoder.decode(Model.Collection.self, from: data)
                    return collection
                }
                callback(.success(collection))
            } catch {
                callback(.failure(error))
            }
        }
    }

    func list(identifiers: [Model.CollectionIdentifier]? = nil,
              callback: @escaping (Result<[Model.Collection], Error>) -> Void) {
        // try read to cache
        let cached = self.cacheLock.withLock {
            identifiers?.compactMap { identifier in
                self.cache[identifier]
            }
        }
        if let cached = cached, cached.count > 0, cached.count == identifiers?.count {
            return callback(.success(cached))
        }

        // go to db if not found
        self.queue.async {
            do {
                var blobs = [Data]()
                if let identifiers = identifiers {
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

                // decoding is a performance bottleneck (10+s for 1000 collections)
                // workaround is to decode in parallel if list is large enough to justify it
                var collections: [Model.Collection]
                if blobs.count < 50 {
                    // TODO: consider some diagnostics / warning for invalid data
                    collections = blobs.compactMap { data -> Model.Collection? in
                        try? self.decoder.decode(Model.Collection.self, from: data)
                    }
                } else {
                    let lock = Lock()
                    let sync = DispatchGroup()
                    collections = [Model.Collection]()
                    blobs.forEach { data in
                        sync.enter()
                        self.queue.async {
                            defer { sync.leave() }
                            if let collection = try? self.decoder.decode(Model.Collection.self, from: data) {
                                lock.withLock {
                                    collections.append(collection)
                                }
                            }
                        }
                    }
                    sync.wait()
                }

                callback(.success(collections))
            } catch {
                callback(.failure(error))
            }
        }
    }

    // TODO: this is PoC for search, need a more performant version of this
    func searchPackages(identifiers: [Model.CollectionIdentifier]? = nil,
                        query: String,
                        callback: @escaping (Result<Model.PackageSearchResult, Error>) -> Void) {
        let queryString = query.lowercased()

        self.list(identifiers: identifiers) { result in
            switch result {
            case .failure(let error):
                callback(.failure(error))
            case .success(let collections):
                let collectionsPackages = collections.reduce([Model.CollectionIdentifier: [Model.Package]]()) { partial, collection in
                    var map = partial
                    map[collection.identifier] = collection.packages.filter { package in
                        if package.repository.url.lowercased().contains(queryString) { return true }
                        if let summary = package.summary, summary.lowercased().contains(queryString) { return true }
                        if let keywords = package.keywords, (keywords.map { $0.lowercased() }).contains(queryString) { return true }
                        return package.versions.contains(where: { version in
                            if version.packageName.lowercased().contains(queryString) { return true }
                            if version.products.contains(where: { $0.name.lowercased().contains(queryString) }) { return true }
                            return version.targets.contains(where: { $0.name.lowercased().contains(queryString) })
                        })
                    }
                    return map
                }

                // compose result :p

                var packageCollections = [PackageReference: (package: Model.Package, collections: Set<Model.CollectionIdentifier>)]()
                collectionsPackages.forEach { collectionIdentifier, packages in
                    packages.forEach { package in
                        // Avoid copy-on-write: remove entry from dictionary before mutating
                        var entry = packageCollections.removeValue(forKey: package.reference) ?? (package, .init())
                        entry.collections.insert(collectionIdentifier)
                        packageCollections[package.reference] = entry
                    }
                }

                let result = Model.PackageSearchResult(items: packageCollections.map { entry in
                    .init(package: entry.value.package, collections: Array(entry.value.collections))
                })

                callback(.success(result))
            }
        }
    }

    // TODO: this is PoC for search, need a more performant version of this
    func findPackage(identifier: PackageIdentity,
                     collectionIdentifiers: [Model.CollectionIdentifier]?,
                     callback: @escaping (Result<Model.PackageSearchResult.Item, Error>) -> Void) {
        self.list(identifiers: collectionIdentifiers) { result in
            switch result {
            case .failure(let error):
                return callback(.failure(error))
            case .success(let collections):
                // sorting by collection processing date so the latest metadata is first
                let collectionPackages = collections.sorted(by: { lhs, rhs in lhs.lastProcessedAt > rhs.lastProcessedAt }).compactMap { collection in
                    collection.packages
                        .first(where: { $0.reference.identity == identifier })
                        .flatMap { (collection: collection.identifier, package: $0) }
                }
                // first package should have latest processing date
                guard let package = collectionPackages.first?.package else {
                    return callback(.failure(NotFoundError("\(identifier)")))
                }
                let collections = collectionPackages.map { $0.collection }
                callback(.success(.init(package: package, collections: collections)))
            }
        }
    }

    // TODO: this is PoC for search, need a more performant version of this
    func searchTargets(identifiers: [Model.CollectionIdentifier]? = nil,
                       query: String,
                       type: Model.TargetSearchType,
                       callback: @escaping (Result<Model.TargetSearchResult, Error>) -> Void) {
        let query = query.lowercased()

        self.list(identifiers: identifiers) { result in
            switch result {
            case .failure(let error):
                callback(.failure(error))
            case .success(let collections):
                let collectionsPackages = collections.reduce([Model.CollectionIdentifier: [(target: Model.Target, package: Model.Package)]]()) { partial, collection in
                    var map = partial
                    collection.packages.forEach { package in
                        package.versions.forEach { version in
                            version.targets.forEach { target in
                                let match: Bool
                                switch type {
                                case .exactMatch:
                                    match = target.name.lowercased() == query
                                case .prefix:
                                    match = target.name.lowercased().hasPrefix(query)
                                }
                                if match {
                                    // Avoid copy-on-write: remove entry from dictionary before mutating
                                    var entry = map.removeValue(forKey: collection.identifier) ?? .init()
                                    entry.append((target, package))
                                    map[collection.identifier] = entry
                                }
                            }
                        }
                    }
                    return map
                }

                // compose result :p

                var packageCollections = [PackageReference: (package: Model.Package, collections: Set<Model.CollectionIdentifier>)]()
                var targetsPackages = [Model.Target: Set<PackageReference>]()

                collectionsPackages.forEach { collectionIdentifier, packagesAndTargets in
                    packagesAndTargets.forEach { item in
                        // Avoid copy-on-write: remove entry from dictionary before mutating
                        var packageCollectionsEntry = packageCollections.removeValue(forKey: item.package.reference) ?? (item.package, .init())
                        packageCollectionsEntry.collections.insert(collectionIdentifier)
                        packageCollections[item.package.reference] = packageCollectionsEntry

                        // Avoid copy-on-write: remove entry from dictionary before mutating
                        var targetsPackagesEntry = targetsPackages.removeValue(forKey: item.target) ?? .init()
                        targetsPackagesEntry.insert(item.package.reference)
                        targetsPackages[item.target] = targetsPackagesEntry
                    }
                }

                let result = Model.TargetSearchResult(items: targetsPackages.map { target, packages in
                    let targetsPackages = packages
                        .compactMap { packageCollections[$0] }
                        .map { pair -> Model.TargetListItem.Package in
                            let versions = pair.package.versions.map { Model.TargetListItem.Package.Version(version: $0.version, packageName: $0.packageName) }
                            return Model.TargetListItem.Package(repository: pair.package.repository,
                                                                summary: pair.package.summary,
                                                                versions: versions,
                                                                collections: Array(pair.collections))
                        }

                    return Model.TargetListItem(target: target, packages: targetsPackages)
                })

                callback(.success(result))
            }
        }
    }

    // for testing
    internal func resetCache() {
        self.cacheLock.withLock {
            self.cache = [:]
        }
    }

    // MARK: -  Private

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

private extension Model.Collection.Identifier {
    func databaseKey() -> String {
        switch self {
        case .json(let url):
            return url.absoluteString
        }
    }
}
