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

public struct PackageIndexAndCollections: PackageIndexAndCollectionsProtocol {
    private let index: PackageIndexProtocol
    private let collections: PackageCollectionsProtocol
    
    public init(
        collectionsConfiguration: PackageCollections.Configuration = .init(),
        observabilityScope: ObservabilityScope
    ) {
        let index = PackageIndex(
            fileSystem: localFileSystem,
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
    }
    
    init(index: PackageIndexProtocol, collections: PackageCollectionsProtocol) {
        self.index = index
        self.collections = collections
    }
    
    // MARK: - Package collection APIs
    
    public func listCollections(
        identifiers: Set<PackageCollectionsModel.CollectionIdentifier>?,
        callback: @escaping (Result<[PackageCollectionsModel.Collection], Error>) -> Void
    ) {
        self.collections.listCollections(identifiers: identifiers, callback: callback)
    }

    public func refreshCollections(callback: @escaping (Result<[PackageCollectionsModel.CollectionSource], Error>) -> Void) {
        self.collections.refreshCollections(callback: callback)
    }

    public func refreshCollection(
        _ source: PackageCollectionsModel.CollectionSource,
        callback: @escaping (Result<PackageCollectionsModel.Collection, Error>) -> Void
    ) {
        self.collections.refreshCollection(source, callback: callback)
    }

    public func addCollection(
        _ source: PackageCollectionsModel.CollectionSource,
        order: Int?,
        trustConfirmationProvider: ((PackageCollectionsModel.Collection, @escaping (Bool) -> Void) -> Void)?,
        callback: @escaping (Result<PackageCollectionsModel.Collection, Error>) -> Void
    ) {
        self.collections.addCollection(source, order: order, trustConfirmationProvider: trustConfirmationProvider, callback: callback)
    }

    public func removeCollection(
        _ source: PackageCollectionsModel.CollectionSource,
        callback: @escaping (Result<Void, Error>) -> Void
    ) {
        self.collections.removeCollection(source, callback: callback)
    }

    public func getCollection(
        _ source: PackageCollectionsModel.CollectionSource,
        callback: @escaping (Result<PackageCollectionsModel.Collection, Error>) -> Void
    ) {
        self.collections.getCollection(source, callback: callback)
    }

    public func listPackages(
        collections: Set<PackageCollectionsModel.CollectionIdentifier>?,
        callback: @escaping (Result<PackageCollectionsModel.PackageSearchResult, Error>) -> Void
    ) {
        self.collections.listPackages(collections: collections, callback: callback)
    }

    public func listTargets(
        collections: Set<PackageCollectionsModel.CollectionIdentifier>?,
        callback: @escaping (Result<PackageCollectionsModel.TargetListResult, Error>) -> Void
    ) {
        self.collections.listTargets(collections: collections, callback: callback)
    }
    
    public func findTargets(
        _ query: String,
        searchType: PackageCollectionsModel.TargetSearchType?,
        collections: Set<PackageCollectionsModel.CollectionIdentifier>?,
        callback: @escaping (Result<PackageCollectionsModel.TargetSearchResult, Error>) -> Void
    ) {
        self.collections.findTargets(query, searchType: searchType, collections: collections, callback: callback)
    }
    
    // MARK: - Package index APIs

    public func isIndexEnabled(callback: @escaping (Result<Bool, Error>) -> Void) {
        self.index.get { result in
            switch result {
            case .failure(PackageIndexError.featureDisabled):
                callback(.success(false))
            case .failure(let error):
                callback(.failure(error))
            case .success(let url):
                callback(.success(url != .none))
            }
        }
    }

    public func setIndex(
        url: Foundation.URL,
        callback: @escaping (Result<Void, Error>) -> Void
    ) {
        self.index.set(url: url, callback: callback)
    }

    public func unsetIndex(callback: @escaping (Result<Void, Error>) -> Void) {
        self.index.unset(callback: callback)
    }
    
    public func getIndex(callback: @escaping (Result<Foundation.URL?, Error>) -> Void) {
        self.index.get(callback: callback)
    }
    
    public func listPackagesInIndex(
        offset: Int,
        limit: Int,
        callback: @escaping (Result<PackageCollectionsModel.PaginatedPackageList, Error>) -> Void
    ) {
        self.index.listPackages(offset: offset, limit: limit, callback: callback)
    }
    
    // MARK: - APIs that make use of package index and collections
    
    public func getPackageMetadata(
        identity: PackageIdentity,
        location: String?,
        collections: Set<PackageCollectionsModel.CollectionIdentifier>?,
        callback: @escaping (Result<PackageCollectionsModel.PackageMetadata, Error>) -> Void
    ) {
        // Get metadata using both package index and collections
        let sync = DispatchGroup()
        let results = ThreadSafeKeyValueStore<Source, Result<PackageCollectionsModel.PackageMetadata, Error>>()
        DispatchQueue.sharedConcurrent.async {
            sync.enter()
            // This uses package index only
            self.index.getPackageMetadata(identity: identity, location: location) { result in
                defer { sync.leave() }
                results[.index] = result
            }
        }
        DispatchQueue.sharedConcurrent.async {
            sync.enter()
            // This uses either package index or "alternative" (e.g., GitHub) as metadata provider,
            // then merge the supplementary metadata with data coming from collections. The package
            // must belong to at least one collection.
            self.collections.getPackageMetadata(identity: identity, location: location, collections: collections) { result in
                defer { sync.leave() }
                results[.collections] = result
            }
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
                    // Return index's error unless no index is configured.
                    switch indexError {
                    case PackageIndexError.featureDisabled, PackageIndexError.notConfigured:
                        callback(.failure(collectionsError))
                    default:
                        callback(.failure(indexError))
                    }
                }
            }
        }
    }
    
    public func findPackages(
        _ query: String,
        collections: Set<PackageCollectionsModel.CollectionIdentifier>?,
        callback: @escaping (Result<PackageCollectionsModel.PackageSearchResult, Error>) -> Void
    ) {
        self.index.findPackages(query) { indexResult in
            switch indexResult {
            case .failure(PackageIndexError.featureDisabled), .failure(PackageIndexError.notConfigured):
                self.collections.findPackages(query, collections: collections, callback: callback)
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
        self.index.get { result in
            switch result {
            case .success(.some):
                self.index.get(identity: identity, location: location, callback: callback)
            default:
                self.alternative.get(identity: identity, location: location, callback: callback)
            }
        }
    }
}
