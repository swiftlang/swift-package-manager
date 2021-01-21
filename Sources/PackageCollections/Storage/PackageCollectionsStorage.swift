/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import PackageModel

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

    /// Returns optional `PackageSearchResult.Item` for the given package identity.
    ///
    /// - Parameters:
    ///   - identifier: The package identifier
    ///   - collectionIdentifiers: Optional. The identifiers of the `PackageCollection`s
    ///   - callback: The closure to invoke when result becomes available
    func findPackage(identifier: PackageIdentity,
                     collectionIdentifiers: [PackageCollectionsModel.CollectionIdentifier]?,
                     callback: @escaping (Result<PackageCollectionsModel.PackageSearchResult.Item, Error>) -> Void)

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
