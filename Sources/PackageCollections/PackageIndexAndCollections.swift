/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2022 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import Dispatch
import struct Foundation.URL
import PackageModel
import TSCBasic

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
    
    /// - SeeAlso: `PackageCollectionsProtocol.listCollections`
    public func listCollections(
        identifiers: Set<PackageCollectionsModel.CollectionIdentifier>? = nil,
        callback: @escaping (Result<[PackageCollectionsModel.Collection], Error>) -> Void
    ) {
        self.collections.listCollections(identifiers: identifiers, callback: callback)
    }

    /// - SeeAlso: `PackageCollectionsProtocol.refreshCollections`
    public func refreshCollections(callback: @escaping (Result<[PackageCollectionsModel.CollectionSource], Error>) -> Void) {
        self.collections.refreshCollections(callback: callback)
    }

    /// - SeeAlso: `PackageCollectionsProtocol.refreshCollection`
    public func refreshCollection(
        _ source: PackageCollectionsModel.CollectionSource,
        callback: @escaping (Result<PackageCollectionsModel.Collection, Error>) -> Void
    ) {
        self.collections.refreshCollection(source, callback: callback)
    }

    /// - SeeAlso: `PackageCollectionsProtocol.addCollection`
    public func addCollection(
        _ source: PackageCollectionsModel.CollectionSource,
        order: Int? = nil,
        trustConfirmationProvider: ((PackageCollectionsModel.Collection, @escaping (Bool) -> Void) -> Void)? = nil,
        callback: @escaping (Result<PackageCollectionsModel.Collection, Error>) -> Void
    ) {
        self.collections.addCollection(source, order: order, trustConfirmationProvider: trustConfirmationProvider, callback: callback)
    }

    /// - SeeAlso: `PackageCollectionsProtocol.removeCollection`
    public func removeCollection(
        _ source: PackageCollectionsModel.CollectionSource,
        callback: @escaping (Result<Void, Error>) -> Void
    ) {
        self.collections.removeCollection(source, callback: callback)
    }

    /// - SeeAlso: `PackageCollectionsProtocol.getCollection`
    public func getCollection(
        _ source: PackageCollectionsModel.CollectionSource,
        callback: @escaping (Result<PackageCollectionsModel.Collection, Error>) -> Void
    ) {
        self.collections.getCollection(source, callback: callback)
    }

    /// - SeeAlso: `PackageCollectionsProtocol.listPackages`
    public func listPackages(
        collections: Set<PackageCollectionsModel.CollectionIdentifier>? = nil,
        callback: @escaping (Result<PackageCollectionsModel.PackageSearchResult, Error>) -> Void
    ) {
        self.collections.listPackages(collections: collections, callback: callback)
    }

    /// - SeeAlso: `PackageCollectionsProtocol.listTargets`
    public func listTargets(
        collections: Set<PackageCollectionsModel.CollectionIdentifier>? = nil,
        callback: @escaping (Result<PackageCollectionsModel.TargetListResult, Error>) -> Void
    ) {
        self.collections.listTargets(collections: collections, callback: callback)
    }
    
    /// - SeeAlso: `PackageCollectionsProtocol.findTargets`
    public func findTargets(
        _ query: String,
        searchType: PackageCollectionsModel.TargetSearchType? = nil,
        collections: Set<PackageCollectionsModel.CollectionIdentifier>? = nil,
        callback: @escaping (Result<PackageCollectionsModel.TargetSearchResult, Error>) -> Void
    ) {
        self.collections.findTargets(query, searchType: searchType, collections: collections, callback: callback)
    }
    
    // MARK: - Package index specific APIs

    /// Indicates if package index is configured.
    public func isIndexEnabled() -> Bool {
        self.index.isEnabled
    }

    /// - SeeAlso: `PackageIndexProtocol.listPackages`
    public func listPackagesInIndex(
        offset: Int,
        limit: Int,
        callback: @escaping (Result<PackageCollectionsModel.PaginatedPackageList, Error>) -> Void
    ) {
        self.index.listPackages(offset: offset, limit: limit, callback: callback)
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
    ///   - callback: The closure to invoke when result becomes available
    public func getPackageMetadata(
        identity: PackageIdentity,
        location: String? = nil,
        collections: Set<PackageCollectionsModel.CollectionIdentifier>? = nil,
        callback: @escaping (Result<PackageCollectionsModel.PackageMetadata, Error>) -> Void
    ) {
        // Package index not available - fallback to collections
        guard self.index.isEnabled else {
            return self.collections.getPackageMetadata(identity: identity, location: location, collections: collections, callback: callback)
        }
                
        // Get metadata using both package index and collections
        let sync = DispatchGroup()
        let results = ThreadSafeKeyValueStore<Source, Result<PackageCollectionsModel.PackageMetadata, Error>>()

        sync.enter()
        // This uses package index only
        self.index.getPackageMetadata(identity: identity, location: location) { result in
            defer { sync.leave() }
            results[.index] = result
        }

        sync.enter()
        // This uses either package index or "alternative" (e.g., GitHub) as metadata provider,
        // then merge the supplementary metadata with data coming from collections. The package
        // must belong to at least one collection.
        self.collections.getPackageMetadata(identity: identity, location: location, collections: collections) { result in
            defer { sync.leave() }
            results[.collections] = result
        }
        
        sync.notify(queue: .sharedConcurrent) {
            guard let indexResult = results[.index], let collectionsResult = results[.collections] else {
                return callback(.failure(InternalError("Should contain results from package index and collections")))
            }

            switch (indexResult, collectionsResult) {
            case (.success(let metadataResult), _):
                // Metadata from `PackageIndex`
                callback(.success(
                    PackageCollectionsModel.PackageMetadata(
                        package: metadataResult.package,
                        collections: collectionsResult.success?.collections ?? [],
                        provider: metadataResult.provider
                    )
                ))
            case (.failure(let indexError), .success(let metadataResult)):
                self.observabilityScope.emit(warning: "PackageIndex.getPackageMetadata failed: \(indexError)")
                // Metadata from `PackageCollections`, which is a combination of
                // package index/alternative (e.g., GitHub) and collection data.
                callback(.success(metadataResult))
            case (.failure(let indexError), .failure(let collectionsError)):
                // Failed to get metadata through `PackageIndex` and `PackageCollections`.
                // Return index's error.
                self.observabilityScope.emit(warning: "PackageCollections.getPackageMetadata failed: \(collectionsError)")
                callback(.failure(indexError))
            }
        }
    }
    
    /// Finds and returns packages that match the query.
    ///
    /// - Parameters:
    ///   - query: The search query
    ///   - in: Indicates whether to search in the index only, collections only, or both.
    ///         The optional `Set<CollectionIdentifier>` in some enum cases restricts search within those collections only.
    ///   - callback: The closure to invoke when result becomes available
    public func findPackages(
        _ query: String,
        in searchIn: SearchIn = .both(collections: nil),
        callback: @escaping (Result<PackageCollectionsModel.PackageSearchResult, Error>) -> Void
    ) {
        switch searchIn {
        case .index:
            guard self.index.isEnabled else {
                self.observabilityScope.emit(debug: "Package index is not enabled. Returning empty result.")
                return callback(.success(.init(items: [])))
            }
            self.index.findPackages(query, callback: callback)
        case .collections(let collections):
            self.collections.findPackages(query, collections: collections, callback: callback)
        case .both(let collections):
            // Find packages in both package index and collections
            let sync = DispatchGroup()
            let results = ThreadSafeKeyValueStore<Source, Result<PackageCollectionsModel.PackageSearchResult, Error>>()

            sync.enter()
            self.index.findPackages(query) { result in
                defer { sync.leave() }
                results[.index] = result
            }

            sync.enter()
            self.collections.findPackages(query, collections: collections) { result in
                defer { sync.leave() }
                results[.collections] = result
            }
            
            sync.notify(queue: .sharedConcurrent) {
                guard let indexResult = results[.index], let collectionsResult = results[.collections] else {
                    return callback(.failure(InternalError("Should contain results from package index and collections")))
                }

                switch (indexResult, collectionsResult) {
                case (.success(let indexSearchResult), .success(let collectionsSearchResult)):
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
                    
                    callback(.success(PackageCollectionsModel.PackageSearchResult(items: items)))
                case (.success(let indexSearchResult), .failure(let collectionsError)):
                    self.observabilityScope.emit(warning: "PackageCollections.findPackages failed: \(collectionsError)")
                    // Collections query failed, try another way to find the collections that an item belongs to.
                    self.collections.listPackages(collections: collections) { collectionsResult in
                        switch collectionsResult {
                        case .failure:
                            callback(.success(indexSearchResult))
                        case .success(let collectionsSearchResult):
                            let items = indexSearchResult.items.map { item in
                                PackageCollectionsModel.PackageSearchResult.Item(
                                    package: item.package,
                                    collections: collectionsSearchResult.items.first(where: {
                                        item.package.identity == $0.package.identity && item.package.location == $0.package.location
                                    })?.collections ?? [],
                                    indexes: item.indexes
                                )
                            }
                            callback(.success(PackageCollectionsModel.PackageSearchResult(items: items)))
                        }
                    }
                case (.failure(let indexError), .success(let searchResult)):
                    self.observabilityScope.emit(warning: "PackageIndex.findPackages failed: \(indexError)")
                    callback(.success(searchResult))
                case (.failure(let indexError), .failure(let collectionsError)):
                    // Failed to find packages through `PackageIndex` and `PackageCollections`.
                    // Return index's error.
                    self.observabilityScope.emit(warning: "PackageCollections.findPackages failed: \(collectionsError)")
                    callback(.failure(indexError))
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
        location: String,
        callback: @escaping (Result<PackageCollectionsModel.PackageBasicMetadata, Error>, PackageMetadataProviderContext?) -> Void
    ) {
        if self.index.isEnabled {
            self.index.get(identity: identity, location: location, callback: callback)
        } else {
            self.alternative.get(identity: identity, location: location, callback: callback)
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
