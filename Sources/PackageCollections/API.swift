/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import PackageModel
import SourceControl

public protocol PackageCollectionsProtocol {
    // MARK: - Package collection profile APIs

    /// Lists package collection profiles.
    ///
    /// The result of this API does not include `PackageCollection` data. All other APIs in this
    /// protocol require the context of a profile. Implementations should support a "default"
    /// profile such that the `profile` API parameter can be optional.
    ///
    /// - Parameters:
    ///   - callback: The closure to invoke when result becomes available
    func listProfiles(callback: @escaping (Result<[PackageCollectionsModel.Profile], Error>) -> Void)

    // MARK: - Package set APIs

    /// Returns packages organized into collections.
    ///
    /// Package collections are not mutually exclusive; a package may belong to more than one collection. As such,
    /// the ordering of `PackageCollection`s should be preserved and respected during conflict resolution.
    ///
    /// - Parameters:
    ///   - identifers: Optional. If specified, only `PackageCollection`s with matching identifiers will be returned.
    ///   - profile: Optional. The `PackageCollectionProfile` context. By default the `default` profile is used.
    ///   - callback: The closure to invoke when result becomes available
    func listPackageCollections(
        identifers: Set<PackageCollectionsModel.PackageCollectionIdentifier>?,
        in profile: PackageCollectionsModel.Profile?,
        callback: @escaping (Result<[PackageCollectionsModel.PackageCollection], Error>) -> Void
    )

    /// Refreshes all configured package collections.
    ///
    /// - Parameters:
    ///   - profile: Optional. The `PackageCollectionProfile` context. By default the `default` profile is used.
    ///   - callback: The closure to invoke after triggering a refresh for the configured package collections.
    func refreshPackageCollections(
        in profile: PackageCollectionsModel.Profile?,
        callback: @escaping (Result<[PackageCollectionsModel.PackageCollectionSource], Error>) -> Void
    )

    /// Adds a package collection.
    ///
    /// - Parameters:
    ///   - source: The package collection's source
    ///   - order: Optional. The order that the `PackageCollection` should take after being added to the list.
    ///            By default the new collection is appended to the end (i.e., the least relevant order).
    ///   - profile: Optional. The `PackageCollectionProfile` context. By default the `default` profile is used.
    ///   - callback: The closure to invoke with the updated `PackageCollection`s
    func addPackageCollection(
        _ source: PackageCollectionsModel.PackageCollectionSource,
        order: Int?,
        to profile: PackageCollectionsModel.Profile?,
        callback: @escaping (Result<PackageCollectionsModel.PackageCollection, Error>) -> Void
    )

    /// Removes a package collection.
    ///
    /// - Parameters:
    ///   - source: The package collection's source
    ///   - profile: Optional. The `PackageCollectionProfile` context. By default the `default` profile is used.
    ///   - callback: The closure to invoke with the updated `PackageCollection`s
    func removePackageCollection(
        _ source: PackageCollectionsModel.PackageCollectionSource,
        from profile: PackageCollectionsModel.Profile?,
        callback: @escaping (Result<Void, Error>) -> Void
    )

    /// Moves a package collection to a different order.
    ///
    /// - Parameters:
    ///   - id: The identifier of the `PackageCollection` to be moved
    ///   - order: The new order that the `PackageCollection` should be positioned after the move
    ///   - profile: Optional. The `PackageCollectionProfile` context. By default the `default` profile is used.
    ///   - callback: The closure to invoke with the updated `PackageCollection`s
    func movePackageCollection(
        _ source: PackageCollectionsModel.PackageCollectionSource,
        to order: Int,
        in profile: PackageCollectionsModel.Profile?,
        callback: @escaping (Result<Void, Error>) -> Void
    )

    /// Returns information about a package collection. The collection is not required to be in the configured list. If
    /// not found locally, the collection will be fetched from the source.
    ///
    /// - Parameters:
    ///   - source: The package collection's source
    ///   - callback: The closure to invoke with the `PackageCollection`
    func getPackageCollection(
        _ source: PackageCollectionsModel.PackageCollectionSource,
        callback: @escaping (Result<PackageCollectionsModel.PackageCollection, Error>) -> Void
    )

    // MARK: - Package APIs

    /// Returns metadata for the package identified by the given `PackageReference`, along with the
    /// identifiers of `PackageCollection`s where the package is found.
    ///
    /// A failure is returned if the package is not found.
    ///
    /// - Parameters:
    ///   - reference: The package reference
    ///   - profile: Optional. The `PackageCollectionProfile` context. By default the `default` profile is used.
    ///   - callback: The closure to invoke when result becomes available
    func getPackageMetadata(
        _ reference: PackageReference,
        profile: PackageCollectionsModel.Profile?,
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
    ///   - profile: Optional. The `PackageCollectionProfile` context. By default the `default` profile is used.
    ///   - callback: The closure to invoke when result becomes available
    func listTargets(
        collections: Set<PackageCollectionsModel.PackageCollectionIdentifier>?,
        in profile: PackageCollectionsModel.Profile?,
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
    ///   - profile: Optional. The `PackageCollectionProfile` context. By default the `default` profile is used.
    ///   - callback: The closure to invoke when result becomes available
    func findPackages(
        _ query: String,
        collections: Set<PackageCollectionsModel.PackageCollectionIdentifier>?,
        profile: PackageCollectionsModel.Profile?,
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
    ///   - profile: Optional. The `PackageCollectionProfile` context. By default the `default` profile is used.
    ///   - callback: The closure to invoke when result becomes available
    func findTargets(
        _ query: String,
        searchType: PackageCollectionsModel.TargetSearchType?,
        collections: Set<PackageCollectionsModel.PackageCollectionIdentifier>?,
        profile: PackageCollectionsModel.Profile?,
        callback: @escaping (Result<PackageCollectionsModel.TargetSearchResult, Error>) -> Void
    )
}
