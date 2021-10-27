/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import PackageModel

import TSCBasic

/// Package search API provider
protocol PackageSearchProvider {
    /// The name of the provider
    var name: String { get }

    /// Searches for packages using the given query. Packages in the result must belong to an imported package collection.
    ///
    /// - Parameters:
    ///   - query: The search query.
    ///   - collections: Optional. The identifiers of the `PackageCollection`s to filter results on.
    ///   - callback: The closure to invoke when result becomes available.
    func searchPackages(
        _ query: String,
        collections: Set<PackageCollectionsModel.CollectionIdentifier>?,
        callback: @escaping (Result<PackageCollectionsModel.PackageSearchResult, Error>) -> Void
    )

    /// Searches for packages using the given query. Packages in the result do not have to belong to an imported package collection.
    /// In other words, collection-related information in the result can be missing or empty.
    ///
    /// - Parameters:
    ///   - query: The search query.
    ///   - callback: The closure to invoke when result becomes available.
    func searchPackages(
        _ query: String,
        callback: @escaping (Result<PackageCollectionsModel.PackageSearchResult, Error>) -> Void
    )

    /// Finds targets by name and returns the corresponding packages, which must belong to an imported package collection.
    ///
    /// This API's result items will be aggregated by target then package, with the
    /// package's versions list filtered to only include those that contain the target.
    ///
    /// - Parameters:
    ///   - query: The search query
    ///   - searchType: Target names must either match exactly or contain the prefix.
    ///                 For more flexibility, use the `searchPackages` API instead.
    ///   - collections: Optional. The identifiers of the `PackageCollection`s to filter results on.
    ///   - callback: The closure to invoke when result becomes available
    func searchTargets(
        _ query: String,
        searchType: PackageCollectionsModel.TargetSearchType,
        collections: Set<PackageCollectionsModel.CollectionIdentifier>?,
        callback: @escaping (Result<PackageCollectionsModel.TargetSearchResult, Error>) -> Void
    )

    /// Finds targets by name and returns the corresponding packages. Packages do not have to belong to an imported package collection.
    /// In other words, collection-related information in the result can be missing or empty.
    ///
    /// - Parameters:
    ///   - query: The search query
    ///   - searchType: Target names must either match exactly or contain the prefix.
    ///                 For more flexibility, use the `searchPackages` API instead.
    ///   - callback: The closure to invoke when result becomes available
    func searchTargets(
        _ query: String,
        searchType: PackageCollectionsModel.TargetSearchType,
        callback: @escaping (Result<PackageCollectionsModel.TargetSearchResult, Error>) -> Void
    )
}
