/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

/// A `PackageSearchProvider` backed by `PackageCollectionsStorage`.
///
/// Implicitly, packages in search results must belong to an imported collection since that is
/// the only way for a package to be added to storage.
struct StorageBackedPackageSearchProvider: PackageSearchProvider {
    private let storage: PackageCollectionsStorage

    let name: String = "Storage-Backed"

    init(storage: PackageCollectionsStorage) {
        self.storage = storage
    }

    /// Searches for packages in specific imported package collections.
    func searchPackages(_ query: String,
                        collections: Set<PackageCollectionsModel.CollectionIdentifier>?,
                        callback: @escaping (Result<PackageCollectionsModel.PackageSearchResult, Error>) -> Void) {
        self.storage.searchPackages(identifiers: collections.map(Array.init), query: query, callback: callback)
    }

    /// Searches for packages in all imported package collections.
    func searchPackages(_ query: String,
                        callback: @escaping (Result<PackageCollectionsModel.PackageSearchResult, Error>) -> Void) {
        self.searchPackages(query, collections: nil, callback: callback)
    }

    /// Searches for targets in specific imported package collections.
    func searchTargets(_ query: String,
                       searchType: PackageCollectionsModel.TargetSearchType,
                       collections: Set<PackageCollectionsModel.CollectionIdentifier>?,
                       callback: @escaping (Result<PackageCollectionsModel.TargetSearchResult, Error>) -> Void) {
        self.storage.searchTargets(identifiers: collections.map(Array.init), query: query, type: searchType, callback: callback)
    }

    /// Searches for packages in all imported package collections.
    func searchTargets(_ query: String,
                       searchType: PackageCollectionsModel.TargetSearchType,
                       callback: @escaping (Result<PackageCollectionsModel.TargetSearchResult, Error>) -> Void) {
        self.searchTargets(query, searchType: searchType, collections: nil, callback: callback)
    }

    func close() throws {
        // No need to do anything
    }
}
