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

public struct PackageIndexAndCollections {
    private let index: PackageIndexProtocol
    private let collections: PackageCollectionsProtocol
    private let observabilityScope: ObservabilityScope
    
    public init(
        indexConfiguration: PackageIndexConfiguration = .init(),
        collectionsConfiguration: PackageCollections.Configuration = .init(),
        observabilityScope: ObservabilityScope
    ) {
        let index = PackageIndex(
            configuration: indexConfiguration,
            callbackQueue: .sharedConcurrent,
            observabilityScope: observabilityScope
        )
        let metadataProvider = PackageIndexMetadataProvider(
            index: index,
            alternative: GitHubPackageMetadataProvider(
                configuration: .init(authTokens: collectionsConfiguration.authTokens),
                observabilityScope: observabilityScope
            )
        )
        
        self.index = index
        self.collections = PackageCollections(
            configuration: collectionsConfiguration,
            customMetadataProvider: metadataProvider,
            observabilityScope: observabilityScope
        )
        self.observabilityScope = observabilityScope
    }
    
    init(index: PackageIndexProtocol, collections: PackageCollectionsProtocol, observabilityScope: ObservabilityScope) {
        self.index = index
        self.collections = collections
        self.observabilityScope = observabilityScope
    }
    
    // MARK: - Package collection specific APIs
    
    /// - SeeAlso: `PackageCollectionsProtocol.listCollections`
    public func listCollections(
        identifiers: Set<PackageCollectionsModel.CollectionIdentifier>?,
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
        order: Int?,
        trustConfirmationProvider: ((PackageCollectionsModel.Collection, @escaping (Bool) -> Void) -> Void)?,
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
        collections: Set<PackageCollectionsModel.CollectionIdentifier>?,
        callback: @escaping (Result<PackageCollectionsModel.PackageSearchResult, Error>) -> Void
    ) {
        self.collections.listPackages(collections: collections, callback: callback)
    }

    /// - SeeAlso: `PackageCollectionsProtocol.listTargets`
    public func listTargets(
        collections: Set<PackageCollectionsModel.CollectionIdentifier>?,
        callback: @escaping (Result<PackageCollectionsModel.TargetListResult, Error>) -> Void
    ) {
        self.collections.listTargets(collections: collections, callback: callback)
    }
    
    /// - SeeAlso: `PackageCollectionsProtocol.findTargets`
    public func findTargets(
        _ query: String,
        searchType: PackageCollectionsModel.TargetSearchType?,
        collections: Set<PackageCollectionsModel.CollectionIdentifier>?,
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
        location: String?,
        collections: Set<PackageCollectionsModel.CollectionIdentifier>?,
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

            switch indexResult {
            case .success(let metadataResult):
                // Metadata from `PackageIndex`
                callback(.success(
                    PackageCollectionsModel.PackageMetadata(
                        package: metadataResult.package,
                        collections: collectionsResult.success?.collections ?? [],
                        provider: metadataResult.provider
                    )
                ))
            case .failure(let indexError):
                switch collectionsResult {
                case .success(let metadataResult):
                    // Metadata from `PackageCollections`, which is a combination of
                    // package index/alternative (e.g., GitHub) and collection data.
                    callback(.success(
                        PackageCollectionsModel.PackageMetadata(
                            package: metadataResult.package,
                            collections: metadataResult.collections,
                            provider: metadataResult.provider
                        )
                    ))
                case .failure(let collectionsError):
                    // Failed to get metadata through `PackageIndex` and `PackageCollections`.
                    // Return index's error.
                    self.observabilityScope.emit(warning: "PackageCollections.getPackageMetadata failed: \(collectionsError)")
                    callback(.failure(indexError))
                }
            }
        }
    }
    
    /// Finds and returns packages that match the query.
    ///
    /// - Parameters:
    ///   - query: The search query
    ///   - collections: Optional. If specified, only search within these collections.
    ///   - callback: The closure to invoke when result becomes available
    public func findPackages(
        _ query: String,
        collections: Set<PackageCollectionsModel.CollectionIdentifier>?,
        callback: @escaping (Result<PackageCollectionsModel.PackageSearchResult, Error>) -> Void
    ) {
        // Package index not available - fallback to collections
        guard self.index.isEnabled else {
            return self.collections.findPackages(query, collections: collections, callback: callback)
        }
        
        self.index.findPackages(query) { indexResult in
            switch indexResult {
            case .failure(let error):
                callback(.failure(error))
            case .success(let indexSearchResult):
                // For each package in the search result, find the collections that it belongs to.
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
            }
        }
    }
    
    private enum Source: Hashable {
        case index
        case collections
    }
}

struct PackageIndexMetadataProvider: PackageMetadataProvider {
    let index: PackageIndex
    let alternative: PackageMetadataProvider

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
}
