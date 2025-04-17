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
    func put(collection: PackageCollectionsModel.Collection) async throws -> PackageCollectionsModel.Collection

    /// Removes `PackageCollection` from storage.
    ///
    /// - Parameters:
    ///   - identifier: The identifier of the `PackageCollection`
    func remove(identifier: PackageCollectionsModel.CollectionIdentifier) async throws

    /// Returns `PackageCollection` for the given identifier.
    ///
    /// - Parameters:
    ///   - identifier: The identifier of the `PackageCollection`
    func get(identifier: PackageCollectionsModel.CollectionIdentifier) async throws -> PackageCollectionsModel.Collection

    /// Returns `PackageCollection`s for the given identifiers, or all if none specified.
    ///
    /// - Parameters:
    ///   - identifiers: Optional. The identifiers of the `PackageCollection`
    func list(identifiers: [PackageCollectionsModel.CollectionIdentifier]?) async throws -> [PackageCollectionsModel.Collection]

    /// Returns `PackageSearchResult` for the given search criteria.
    ///
    /// - Parameters:
    ///   - identifiers: Optional. The identifiers of the `PackageCollection`s
    ///   - query: The search query expression
    func searchPackages(
        identifiers: [PackageCollectionsModel.CollectionIdentifier]?,
        query: String
    ) async throws -> PackageCollectionsModel.PackageSearchResult

    /// Returns packages for the given package identity.
    ///
    /// Since a package identity can be associated with more than one repository URL, the result may contain multiple items.
    ///
    /// - Parameters:
    ///   - identifier: The package identifier
    ///   - collectionIdentifiers: Optional. The identifiers of the `PackageCollection`s
    func findPackage(
        identifier: PackageIdentity,
        collectionIdentifiers: [PackageCollectionsModel.CollectionIdentifier]?
    ) async throws -> (packages: [PackageCollectionsModel.Package], collections: [PackageCollectionsModel.CollectionIdentifier])

    /// Returns `TargetSearchResult` for the given search criteria.
    ///
    /// - Parameters:
    ///   - identifiers: Optional. The identifiers of the `PackageCollection`
    ///   - query: The search query expression
    ///   - type: The search type
    func searchTargets(
        identifiers: [PackageCollectionsModel.CollectionIdentifier]?,
        query: String,
        type: PackageCollectionsModel.TargetSearchType
    ) async throws -> PackageCollectionsModel.TargetSearchResult
}
