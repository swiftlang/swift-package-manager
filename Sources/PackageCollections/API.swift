/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020-2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import PackageModel
import SourceControl

public protocol PackageCollectionsProtocol {
    // MARK: - Package collection APIs

    /// Returns packages organized into collections.
    ///
    /// Package collections are not mutually exclusive; a package may belong to more than one collection. As such,
    /// the ordering of `PackageCollection`s should be preserved and respected during conflict resolution.
    ///
    /// - Parameters:
    ///   - identifiers: Optional. If specified, only `PackageCollection`s with matching identifiers will be returned.
    ///   - callback: The closure to invoke when result becomes available
    func listCollections(
        identifiers: Set<PackageCollectionsModel.CollectionIdentifier>?,
        callback: @escaping (Result<[PackageCollectionsModel.Collection], Error>) -> Void
    )

    /// Refreshes all configured package collections.
    ///
    /// - Parameters:
    ///   - callback: The closure to invoke after triggering a refresh for the configured package collections.
    func refreshCollections(callback: @escaping (Result<[PackageCollectionsModel.CollectionSource], Error>) -> Void)

    /// Refreshes a package collection.
    ///
    /// - Parameters:
    ///   - source: The package collection to be refreshed
    ///   - callback: The closure to invoke with the refreshed `PackageCollection`
    func refreshCollection(
        _ source: PackageCollectionsModel.CollectionSource,
        callback: @escaping (Result<PackageCollectionsModel.Collection, Error>) -> Void
    )

    /// Adds a package collection.
    ///
    /// - Parameters:
    ///   - source: The package collection's source
    ///   - order: Optional. The order that the `PackageCollection` should take after being added to the list.
    ///            By default the new collection is appended to the end (i.e., the least relevant order).
    ///   - trustConfirmationProvider: The closure to invoke when the collection is not signed and user confirmation is required to proceed
    ///   - callback: The closure to invoke with the newly added `PackageCollection`
    func addCollection(
        _ source: PackageCollectionsModel.CollectionSource,
        order: Int?,
        trustConfirmationProvider: ((PackageCollectionsModel.Collection, @escaping (Bool) -> Void) -> Void)?,
        callback: @escaping (Result<PackageCollectionsModel.Collection, Error>) -> Void
    )

    /// Removes a package collection.
    ///
    /// - Parameters:
    ///   - source: The package collection's source
    ///   - callback: The closure to invoke with the result becomes available
    func removeCollection(
        _ source: PackageCollectionsModel.CollectionSource,
        callback: @escaping (Result<Void, Error>) -> Void
    )

    /// Moves a package collection to a different order.
    ///
    /// - Parameters:
    ///   - source: The source of the `PackageCollection` to be reordered
    ///   - order: The new order that the `PackageCollection` should be positioned after the move
    ///   - callback: The closure to invoke with the result becomes available
    func moveCollection(
        _ source: PackageCollectionsModel.CollectionSource,
        to order: Int,
        callback: @escaping (Result<Void, Error>) -> Void
    )

    /// Updates settings of a `PackageCollection` source (e.g., if it is trusted or not).
    ///
    /// - Parameters:
    ///   - source: The `PackageCollection` source to be updated
    ///   - callback: The closure to invoke when result becomes available
    func updateCollection(
        _ source: PackageCollectionsModel.CollectionSource,
        callback: @escaping (Result<PackageCollectionsModel.Collection, Error>) -> Void
    )

    /// Returns information about a package collection. The collection is not required to be in the configured list. If
    /// not found locally, the collection will be fetched from the source.
    ///
    /// - Parameters:
    ///   - source: The package collection's source
    ///   - callback: The closure to invoke with the `PackageCollection`
    func getCollection(
        _ source: PackageCollectionsModel.CollectionSource,
        callback: @escaping (Result<PackageCollectionsModel.Collection, Error>) -> Void
    )

    // MARK: - Package APIs

    /// Returns metadata for the package identified by the given `PackageReference`, along with the
    /// identifiers of `PackageCollection`s where the package is found.
    ///
    /// A failure is returned if the package is not found.
    ///
    /// - Parameters:
    ///   - reference: The package reference
    ///   - callback: The closure to invoke when result becomes available
    func getPackageMetadata(
        _ reference: PackageReference,
        callback: @escaping (Result<PackageCollectionsModel.PackageMetadata, Error>) -> Void
    )

    // MARK: - Target (Module) APIs

    /// List all known targets.
    ///
    /// A target name may be found in different packages and/or different versions of a package, and a package
    /// may belong to multiple package collections. This API's result items will be consolidated by target then package,
    /// with the package's versions list filtered to only include those that contain the target.
    ///
    /// - Parameters:
    ///   - collections: Optional. If specified, only list targets within these collections.
    ///   - callback: The closure to invoke when result becomes available
    func listTargets(
        collections: Set<PackageCollectionsModel.CollectionIdentifier>?,
        callback: @escaping (Result<PackageCollectionsModel.TargetListResult, Error>) -> Void
    )

    // MARK: - Search APIs

    /// Finds and returns packages that match the query.
    ///
    /// If applicable, for example when we search by package name which might change between versions,
    /// the versions list in the result will be filtered to only include those matching the query.
    ///
    /// - Parameters:
    ///   - query: The search query
    ///   - collections: Optional. If specified, only search within these collections.
    ///   - callback: The closure to invoke when result becomes available
    func findPackages(
        _ query: String,
        collections: Set<PackageCollectionsModel.CollectionIdentifier>?,
        callback: @escaping (Result<PackageCollectionsModel.PackageSearchResult, Error>) -> Void
    )

    /// Finds targets by name and returns the corresponding packages.
    ///
    /// This API's result items will be consolidated by target then package, with the
    /// package's versions list filtered to only include those that contain the target.
    ///
    /// - Parameters:
    ///   - query: The search query
    ///   - searchType: Optional. Target names must either match exactly or contain the prefix.
    ///                 For more flexibility, use the `findPackages` API instead.
    ///   - collections: Optional. If specified, only search within these collections.
    ///   - callback: The closure to invoke when result becomes available
    func findTargets(
        _ query: String,
        searchType: PackageCollectionsModel.TargetSearchType?,
        collections: Set<PackageCollectionsModel.CollectionIdentifier>?,
        callback: @escaping (Result<PackageCollectionsModel.TargetSearchResult, Error>) -> Void
    )
}

public enum PackageCollectionError: Equatable, Error {
    /// Package collection is not signed and there is no record of user's trust selection
    case trustConfirmationRequired

    /// Package collection is not signed and user explicitly marks it untrusted
    case untrusted

    /// There are no trusted root certificates. Signature check cannot be done in this case since it involves validating
    /// the certificate chain that is used for signing and one requirement is that the root certificate must be trusted.
    case cannotVerifySignature
}
