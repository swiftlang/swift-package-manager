//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Dispatch
import struct Foundation.URL
import PackageModel

import protocol TSCBasic.Closable

public struct PackageIndexAndCollections: Closable {
    private let index: PackageIndexProtocol
    private let collections: PackageCollectionsProtocol
    private let observabilityScope: ObservabilityScope
    
    public init(
        indexConfiguration: PackageIndexConfiguration = .init(),
        collectionsConfiguration: PackageCollections.Configuration = .init(),
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope
    ) {
        let index = PackageIndex(
            configuration: indexConfiguration,
            callbackQueue: .sharedConcurrent,
            observabilityScope: observabilityScope
        )
        let metadataProvider = PackageIndexMetadataProvider(
            index: index,
            alternativeContainer: (
                provider: GitHubPackageMetadataProvider(
                    configuration: .init(authTokens: collectionsConfiguration.authTokens),
                    observabilityScope: observabilityScope
                ),
                managed: true
            )
        )
        
        self.index = index
        self.collections = PackageCollections(
            configuration: collectionsConfiguration,
            customMetadataProvider: metadataProvider,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope
        )
        self.observabilityScope = observabilityScope
    }
    
    init(index: PackageIndexProtocol, collections: PackageCollectionsProtocol, observabilityScope: ObservabilityScope) {
        self.index = index
        self.collections = collections
        self.observabilityScope = observabilityScope
    }
    
    public func close() throws {
        if let index = self.index as? Closable {
            try index.close()
        }
        if let collections = self.collections as? Closable {
            try collections.close()
        }
    }
    
    // MARK: - Package collection specific APIs
    
    public func listCollections(
        identifiers: Set<PackageCollectionsModel.CollectionIdentifier>? = nil
    ) async throws -> [PackageCollectionsModel.Collection] {
        try await self.collections.listCollections(identifiers: identifiers)
    }

    
    public func refreshCollections() async throws -> [PackageCollectionsModel.CollectionSource] {
        try await self.collections.refreshCollections()
    }

    public func refreshCollection(_ source: PackageCollectionsModel.CollectionSource) async throws -> PackageCollectionsModel.Collection {
        try await self.collections.refreshCollection(source)
    }

    public func addCollection(
        _ source: PackageCollectionsModel.CollectionSource,
        order: Int? = nil,
        trustConfirmationProvider: ((PackageCollectionsModel.Collection, @escaping (Bool) -> Void) -> Void)? = nil
    ) async throws -> PackageCollectionsModel.Collection {
        try await self.collections.addCollection(
            source,
            order: order,
            trustConfirmationProvider: trustConfirmationProvider
        )
    }
    
    public func removeCollection(
        _ source: PackageCollectionsModel.CollectionSource
    ) async throws {
        try await self.collections.removeCollection(source)
    }

    public func getCollection(
        _ source: PackageCollectionsModel.CollectionSource
    ) async throws -> PackageCollectionsModel.Collection {
        try await self.collections.getCollection(source)
    }

    public func listPackages(
        collections: Set<PackageCollectionsModel.CollectionIdentifier>? = nil
    ) async throws -> PackageCollectionsModel.PackageSearchResult {
        try await self.collections.listPackages(collections: collections)
    }
    
    public func listTargets(
        collections: Set<PackageCollectionsModel.CollectionIdentifier>? = nil
    ) async throws -> PackageCollectionsModel.TargetListResult {
        try await self.collections.listTargets(collections: collections)
    }

    public func findTargets(
        _ query: String,
        searchType: PackageCollectionsModel.TargetSearchType? = nil,
        collections: Set<PackageCollectionsModel.CollectionIdentifier>? = nil
    ) async throws -> PackageCollectionsModel.TargetSearchResult {
        try await self.collections.findTargets(
            query,
            searchType: searchType,
            collections: collections
        )
    }


    // MARK: - Package index specific APIs

    /// Indicates if package index is configured.
    public func isIndexEnabled() -> Bool {
        self.index.isEnabled
    }
    
    public func listPackagesInIndex(
        offset: Int,
        limit: Int
    ) async throws -> PackageCollectionsModel.PaginatedPackageList {
        try await self.index.listPackages(offset: offset, limit: limit)
    }


    // MARK: - APIs that make use of both package index and collections

    /// Returns metadata for the package identified by the given `PackageIdentity`, using package index (if configured)
    /// and collections data.
    ///
    /// A failure is returned if the package is not found.
    ///
    /// - Parameters:
    ///   - identity: The package identity
    ///   - location: The package location (optional for deduplication)
    ///   - collections: Optional. If specified, only these collections are used to construct the result.
    public func getPackageMetadata(
        identity: PackageIdentity,
        location: String? = nil,
        collections: Set<PackageCollectionsModel.CollectionIdentifier>? = nil
    ) async throws -> PackageCollectionsModel.PackageMetadata {
        // Package index not available - fallback to collections
        guard self.index.isEnabled else {
            return try await self.collections.getPackageMetadata(identity: identity, location: location, collections: collections)
        }

        // This uses package index only
        async let indexResult = self.index.getPackageMetadata(identity: identity, location: location)

        // This uses either package index or "alternative" (e.g., GitHub) as metadata provider,
        // then merge the supplementary metadata with data coming from collections. The package
        // must belong to at least one collection.
        async let collectionsResult = self.collections.getPackageMetadata(identity: identity, location: location, collections: collections)


        do {
            let indexPackageMetadata = try await indexResult
            return PackageCollectionsModel.PackageMetadata(
                package: indexPackageMetadata.package,
                collections: (try? await collectionsResult)?.collections ?? [],
                provider: indexPackageMetadata.provider
            )
        } catch {
            self.observabilityScope.emit(warning: "PackageIndex.getPackageMetadata failed: \(error)")
            do {
                return try await collectionsResult
            } catch let collectionsError {
                self.observabilityScope.emit(warning: "PackageCollections.getPackageMetadata failed: \(collectionsError)")
            }
            throw error
        }
    }

    /// Finds and returns packages that match the query.
    ///
    /// - Parameters:
    ///   - query: The search query
    ///   - in: Indicates whether to search in the index only, collections only, or both.
    ///         The optional `Set<CollectionIdentifier>` in some enum cases restricts search within those collections only.
    public func findPackages(
        _ query: String,
        in searchIn: SearchIn = .both(collections: nil)
    ) async throws -> PackageCollectionsModel.PackageSearchResult {
        switch searchIn {
        case .index:
            guard self.index.isEnabled else {
                self.observabilityScope.emit(debug: "Package index is not enabled. Returning empty result.")
                return PackageCollectionsModel.PackageSearchResult(items: [])
            }
            return try await self.index.findPackages(query)
        case .collections(let collections):
            return try await self.collections.findPackages(query, collections: collections)
        case .both(let collections):
            // Find packages in both package index and collections
            async let pendingIndexPackages = self.index.findPackages(query)
            async let pendingcollectionPackages = self.collections.findPackages(query, collections: collections)

            do {
                let indexSearchResult = try await pendingIndexPackages
                do {
                    let collectionsSearchResult = try await pendingcollectionPackages

                    let indexItems = Dictionary(uniqueKeysWithValues: indexSearchResult.items.map {
                        (SearchResultItemKey(identity: $0.package.identity, location: $0.package.location), $0)
                    })
                    let collectionItems = Dictionary(uniqueKeysWithValues: collectionsSearchResult.items.map {
                        (SearchResultItemKey(identity: $0.package.identity, location: $0.package.location), $0)
                    })

                    // An array of combined results, with index items listed first.
                    var items = [PackageCollectionsModel.PackageSearchResult.Item]()
                    // Iterating through the dictionary would simplify the code, but we want to keep the ordering of the search result.
                    indexSearchResult.items.forEach {
                        var item = $0
                        let key = SearchResultItemKey(identity: $0.package.identity, location: $0.package.location)
                        // This item is found in collections too
                        if let collectionsMatch = collectionItems[key] {
                            item.collections = collectionsMatch.collections
                        }
                        items.append(item)
                    }
                    collectionsSearchResult.items.forEach {
                        let key = SearchResultItemKey(identity: $0.package.identity, location: $0.package.location)
                        // This item is found in index as well, but skipping since it has already been handled in the loop above.
                        guard indexItems[key] == nil else {
                            return
                        }
                        items.append($0)
                    }
                    return PackageCollectionsModel.PackageSearchResult(items: items)

                } catch let collectionsError {
                    self.observabilityScope.emit(warning: "PackageCollections.findPackages failed: \(collectionsError)")

                    // Collections query failed, try another way to find the collections that an item belongs to.
                    do {
                        let collectionsSearchResult = try await self.collections.listPackages(collections: collections)
                        let items = indexSearchResult.items.map { item in
                            PackageCollectionsModel.PackageSearchResult.Item(
                                package: item.package,
                                collections: collectionsSearchResult.items.first(where: {
                                    item.package.identity == $0.package.identity && item.package.location == $0.package.location
                                })?.collections ?? [],
                                indexes: item.indexes
                            )
                        }
                        return PackageCollectionsModel.PackageSearchResult(items: items)
                    } catch {
                        return indexSearchResult
                    }
                }
            } catch let indexError {
                self.observabilityScope.emit(warning: "PackageIndex.findPackages failed: \(indexError)")
                do {
                    return try await pendingcollectionPackages
                } catch let collectionsError {
                    // Failed to find packages through `PackageIndex` and `PackageCollections`.
                    // Return index's error.
                    self.observabilityScope.emit(warning: "PackageCollections.findPackages failed: \(collectionsError)")
                    throw indexError
                }
            }

            struct SearchResultItemKey: Hashable {
                let identity: PackageIdentity
                let location: String
            }
        }
    }
    
    private enum Source: Hashable {
        case index
        case collections
    }
}

struct PackageIndexMetadataProvider: PackageMetadataProvider, Closable {
    typealias ProviderContainer = (provider: PackageMetadataProvider, managed: Bool)
    
    let index: PackageIndex
    let alternativeContainer: ProviderContainer
    
    var alternative: PackageMetadataProvider {
        self.alternativeContainer.provider
    }

    func get(
        identity: PackageIdentity,
        location: String
    ) async -> (Result<PackageCollectionsModel.PackageBasicMetadata, Error>, PackageMetadataProviderContext?) {
        if self.index.isEnabled {
            return await self.index.get(identity: identity, location: location)
        } else {
            return await self.alternative.get(identity: identity, location: location)
        }
    }
    
    func close() throws {
        guard self.alternativeContainer.managed else {
            return
        }
        if let alternative = self.alternative as? Closable {
            try alternative.close()
        }
    }
}

extension PackageIndexAndCollections {
    public enum SearchIn {
        case index
        case collections(Set<PackageCollectionsModel.CollectionIdentifier>?)
        case both(collections: Set<PackageCollectionsModel.CollectionIdentifier>?)
    }
}
