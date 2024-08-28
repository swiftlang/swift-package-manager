//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct Foundation.URL
import PackageModel
import SourceControl
import Basics

// MARK: - Package collection

public protocol PackageCollectionsProtocol {
    // MARK: - Package collection APIs

    /// Returns packages organized into collections.
    ///
    /// Package collections are not mutually exclusive; a package may belong to more than one collection. As such,
    /// the ordering of `PackageCollection`s should be preserved and respected during conflict resolution.
    ///
    /// - Parameters:
    ///   - identifiers: Optional. If specified, only `PackageCollection`s with matching identifiers will be returned.
    func listCollections(
        identifiers: Set<PackageCollectionsModel.CollectionIdentifier>?
    ) async throws -> [PackageCollectionsModel.Collection]

    /// Refreshes all configured package collections.
    func refreshCollections() async throws -> [PackageCollectionsModel.CollectionSource]

    /// Refreshes a package collection.
    ///
    /// - Parameters:
    ///   - source: The package collection to be refreshed
    func refreshCollection(
        _ source: PackageCollectionsModel.CollectionSource
    ) async throws -> PackageCollectionsModel.Collection

    /// Adds a package collection.
    ///
    /// - Parameters:
    ///   - source: The package collection's source
    ///   - order: Optional. The order that the `PackageCollection` should take after being added to the list.
    ///            By default the new collection is appended to the end (i.e., the least relevant order).
    ///   - trustConfirmationProvider: The closure to invoke when the collection is not signed and user confirmation is required to proceed
    func addCollection(
        _ source: PackageCollectionsModel.CollectionSource,
        order: Int?,
        trustConfirmationProvider: ((PackageCollectionsModel.Collection, @escaping (Bool) -> Void) -> Void)?
    ) async throws -> PackageCollectionsModel.Collection

    /// Removes a package collection.
    ///
    /// - Parameters:
    ///   - source: The package collection's source
    func removeCollection(
        _ source: PackageCollectionsModel.CollectionSource
    ) async throws

    /// Moves a package collection to a different order.
    ///
    /// - Parameters:
    ///   - source: The source of the `PackageCollection` to be reordered
    ///   - order: The new order that the `PackageCollection` should be positioned after the move
    func moveCollection(
        _ source: PackageCollectionsModel.CollectionSource,
        to order: Int
    ) async throws

    /// Updates settings of a `PackageCollection` source (e.g., if it is trusted or not).
    ///
    /// - Parameters:
    ///   - source: The `PackageCollection` source to be updated
    func updateCollection(
        _ source: PackageCollectionsModel.CollectionSource
    ) async throws -> PackageCollectionsModel.Collection

    /// Returns information about a package collection. The collection is not required to be in the configured list. If
    /// not found locally, the collection will be fetched from the source.
    ///
    /// - Parameters:
    ///   - source: The package collection's source
    func getCollection(
        _ source: PackageCollectionsModel.CollectionSource
    ) async throws -> PackageCollectionsModel.Collection

    /// Returns metadata for the package identified by the given `PackageIdentity`, along with the
    /// identifiers of `PackageCollection`s where the package is found.
    ///
    /// A failure is returned if the package is not found.
    ///
    /// - Parameters:
    ///   - identity: The package identity
    ///   - location: The package location (optional for deduplication)
    ///   - collections: Optional. If specified, only look for package in these collections. Data from the most recently
    ///                  processed collection will be used.
    func getPackageMetadata(
        identity: PackageIdentity,
        location: String?,
        collections: Set<PackageCollectionsModel.CollectionIdentifier>?
    ) async throws -> PackageCollectionsModel.PackageMetadata

    /// Lists packages from the specified collections.
    ///
    /// - Parameters:
    ///   - collections: Optional. If specified, only packages in these collections are included.
    func listPackages(
        collections: Set<PackageCollectionsModel.CollectionIdentifier>?
    ) async throws -> PackageCollectionsModel.PackageSearchResult

    // MARK: - Target (Module) APIs

    /// List all known targets.
    ///
    /// A target name may be found in different packages and/or different versions of a package, and a package
    /// may belong to multiple package collections. This API's result items will be consolidated by target then package,
    /// with the package's versions list filtered to only include those that contain the target.
    ///
    /// - Parameters:
    ///   - collections: Optional. If specified, only list targets within these collections.
    func listTargets(
        collections: Set<PackageCollectionsModel.CollectionIdentifier>?
    ) async throws -> PackageCollectionsModel.TargetListResult

    // MARK: - Search APIs

    /// Finds and returns packages that match the query.
    ///
    /// If applicable, for example when we search by package name which might change between versions,
    /// the versions list in the result will be filtered to only include those matching the query.
    ///
    /// - Parameters:
    ///   - query: The search query
    ///   - collections: Optional. If specified, only search within these collections.
    func findPackages(
        _ query: String,
        collections: Set<PackageCollectionsModel.CollectionIdentifier>?
    ) async throws -> PackageCollectionsModel.PackageSearchResult

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
    func findTargets(
        _ query: String,
        searchType: PackageCollectionsModel.TargetSearchType?,
        collections: Set<PackageCollectionsModel.CollectionIdentifier>?
    ) async throws -> PackageCollectionsModel.TargetSearchResult
}


public enum PackageCollectionError: Equatable, Error {
    /// Package collection is not signed and there is no record of user's trust selection
    case trustConfirmationRequired

    /// Package collection is not signed and user explicitly marks it untrusted
    case untrusted

    /// There are no trusted root certificates. Signature check cannot be done in this case since it involves validating
    /// the certificate chain that is used for signing and one requirement is that the root certificate must be trusted.
    case cannotVerifySignature

    case invalidSignature

    case missingSignature

    case unsupportedPlatform
}

// MARK: - Package index

public protocol PackageIndexProtocol {
    /// Returns true if the package index is configured.
    var isEnabled: Bool { get }
    
    /// Returns metadata for the package identified by the given `PackageIdentity`.
    ///
    /// A failure is returned if the package is not found.
    ///
    /// - Parameters:
    ///   - identity: The package identity
    ///   - location: The package location (optional for deduplication)
    func getPackageMetadata(
        identity: PackageIdentity,
        location: String?
    ) async throws -> PackageCollectionsModel.PackageMetadata

    /// Finds and returns packages that match the query.
    ///
    /// - Parameters:
    ///   - query: The search query
    func findPackages(
        _ query: String
    ) async throws -> PackageCollectionsModel.PackageSearchResult

    /// A paginated list of packages in the index.
    ///
    /// - Parameters:
    ///   - offset: Offset of the first item in the result
    ///   - limit: Number of items to return in the result. Implementations might impose a threshold for this.
    func listPackages(
        offset: Int,
        limit: Int
    ) async throws -> PackageCollectionsModel.PaginatedPackageList
}

public enum PackageIndexError: Equatable, Error {
    /// Package index support is disabled
    case featureDisabled
    /// No package index configured
    case notConfigured
    
    case invalidURL(URL)
    case invalidResponse(URL, String)
}
