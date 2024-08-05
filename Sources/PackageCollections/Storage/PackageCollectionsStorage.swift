//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020-2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import _Concurrency
import PackageModel
import Basics

public protocol PackageCollectionsStorage {
    /// Writes `PackageCollection` to storage.
    ///
    /// - Parameters:
    ///   - collection: The `PackageCollection`
    ///   - callback: The closure to invoke when result becomes available
    @available(*, noasync, message: "Use the async alternative")
    func put(collection: PackageCollectionsModel.Collection,
             callback: @escaping (Result<PackageCollectionsModel.Collection, Error>) -> Void)

    /// Removes `PackageCollection` from storage.
    ///
    /// - Parameters:
    ///   - identifier: The identifier of the `PackageCollection`
    ///   - callback: The closure to invoke when result becomes available
    @available(*, noasync, message: "Use the async alternative")
    func remove(identifier: PackageCollectionsModel.CollectionIdentifier,
                callback: @escaping (Result<Void, Error>) -> Void)

    /// Returns `PackageCollection` for the given identifier.
    ///
    /// - Parameters:
    ///   - identifier: The identifier of the `PackageCollection`
    ///   - callback: The closure to invoke when result becomes available
    @available(*, noasync, message: "Use the async alternative")
    func get(identifier: PackageCollectionsModel.CollectionIdentifier,
             callback: @escaping (Result<PackageCollectionsModel.Collection, Error>) -> Void)

    /// Returns `PackageCollection`s for the given identifiers, or all if none specified.
    ///
    /// - Parameters:
    ///   - identifiers: Optional. The identifiers of the `PackageCollection`
    ///   - callback: The closure to invoke when result becomes available
    @available(*, noasync, message: "Use the async alternative")
    func list(identifiers: [PackageCollectionsModel.CollectionIdentifier]?,
              callback: @escaping (Result<[PackageCollectionsModel.Collection], Error>) -> Void)

    /// Returns `PackageSearchResult` for the given search criteria.
    ///
    /// - Parameters:
    ///   - identifiers: Optional. The identifiers of the `PackageCollection`s
    ///   - query: The search query expression
    ///   - callback: The closure to invoke when result becomes available
    @available(*, noasync, message: "Use the async alternative")
    func searchPackages(identifiers: [PackageCollectionsModel.CollectionIdentifier]?,
                        query: String,
                        callback: @escaping (Result<PackageCollectionsModel.PackageSearchResult, Error>) -> Void)

    /// Returns packages for the given package identity.
    ///
    /// Since a package identity can be associated with more than one repository URL, the result may contain multiple items.
    ///
    /// - Parameters:
    ///   - identifier: The package identifier
    ///   - collectionIdentifiers: Optional. The identifiers of the `PackageCollection`s
    ///   - callback: The closure to invoke when result becomes available
    @available(*, noasync, message: "Use the async alternative")
    func findPackage(identifier: PackageIdentity,
                     collectionIdentifiers: [PackageCollectionsModel.CollectionIdentifier]?,
                     callback: @escaping (Result<(packages: [PackageCollectionsModel.Package], collections: [PackageCollectionsModel.CollectionIdentifier]), Error>) -> Void)

    /// Returns `TargetSearchResult` for the given search criteria.
    ///
    /// - Parameters:
    ///   - identifiers: Optional. The identifiers of the `PackageCollection`
    ///   - query: The search query expression
    ///   - type: The search type
    ///   - callback: The closure to invoke when result becomes available
    @available(*, noasync, message: "Use the async alternative")
    func searchTargets(identifiers: [PackageCollectionsModel.CollectionIdentifier]?,
                       query: String,
                       type: PackageCollectionsModel.TargetSearchType,
                       callback: @escaping (Result<PackageCollectionsModel.TargetSearchResult, Error>) -> Void)
}

public extension PackageCollectionsStorage {
    func put(collection: PackageCollectionsModel.Collection) async throws -> PackageCollectionsModel.Collection {
        try await withCheckedThrowingContinuation {
            self.put(collection: collection, callback: $0.resume(with:))
        }
    }
    func remove(identifier: PackageCollectionsModel.CollectionIdentifier) async throws {
        try await withCheckedThrowingContinuation {
            self.remove(identifier: identifier, callback: $0.resume(with:))
        }
    }
    func get(identifier: PackageCollectionsModel.CollectionIdentifier) async throws -> PackageCollectionsModel.Collection {
        try await withCheckedThrowingContinuation {
            self.get(identifier: identifier, callback: $0.resume(with:))
        }
    }
    func list(identifiers: [PackageCollectionsModel.CollectionIdentifier]? = nil) async throws -> [PackageCollectionsModel.Collection] {
        try await withCheckedThrowingContinuation {
            self.list(identifiers: identifiers, callback: $0.resume(with:))
        }
    }

    func searchPackages(
        identifiers: [PackageCollectionsModel.CollectionIdentifier]? = nil,
        query: String
    ) async throws -> PackageCollectionsModel.PackageSearchResult {
        try await withCheckedThrowingContinuation {
            self.searchPackages(identifiers: identifiers, query: query, callback: $0.resume(with:))
        }
    }
    func findPackage(
        identifier: PackageIdentity,
        collectionIdentifiers: [PackageCollectionsModel.CollectionIdentifier]? = nil
    ) async throws -> (packages: [PackageCollectionsModel.Package], collections: [PackageCollectionsModel.CollectionIdentifier]) {
        try await withCheckedThrowingContinuation {
            self.findPackage(identifier: identifier, collectionIdentifiers: collectionIdentifiers, callback: $0.resume(with:))
        }
    }

    func searchTargets(
        identifiers: [PackageCollectionsModel.CollectionIdentifier]? = nil,
        query: String,
        type: PackageCollectionsModel.TargetSearchType
    ) async throws -> PackageCollectionsModel.TargetSearchResult {
        try await withCheckedThrowingContinuation {
            self.searchTargets(identifiers: identifiers, query: query, type: type, callback: $0.resume(with:))
        }
    }
}
