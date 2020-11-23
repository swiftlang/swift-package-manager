/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import PackageModel

protocol PackageCollectionsSearch {
    /// Adds the given `PackageCollectionsModel.Collection` to the search index.
    ///
    /// - Parameters:
    ///   - collection: The `PackageCollectionsModel.Collection` to index
    ///   - callback: The closure to invoke when result becomes available
    func index(collection: Model.Collection,
               callback: @escaping (Result<Void, Error>) -> Void)
    
    /// Removes the `PackageCollectionsModel.Collection` from the search index.
    ///
    /// - Parameters:
    ///   - identifier: The identifier of the `PackageCollectionsModel.Collection` to remove
    ///   - callback: The closure to invoke when result becomes available
    func remove(identifier: Model.CollectionIdentifier,
                callback: @escaping (Result<Void, Error>) -> Void)
    
    /// Returns `PackageSearchResult.Item` for the given package identity.
    ///
    /// - Parameters:
    ///   - identifier: The package identifier
    ///   - collectionIdentifiers: Optional. The identifiers of the `PackageCollectionsModel.Collection`s to search under.
    ///   - callback: The closure to invoke when result becomes available
    func findPackage(identifier: PackageIdentity,
                     collectionIdentifiers: [Model.CollectionIdentifier]?,
                     callback: @escaping (Result<Model.PackageSearchResult.Item, Error>) -> Void)
    
    /// Returns `PackageSearchResult` for the given search criteria.
    ///
    /// - Parameters:
    ///   - identifiers: Optional. The identifiers of the `PackageCollectionsModel.Collection`s to search under.
    ///   - query: The search query expression
    ///   - callback: The closure to invoke when result becomes available
    func searchPackages(identifiers: [Model.CollectionIdentifier]?,
                        query: String,
                        callback: @escaping (Result<Model.PackageSearchResult, Error>) -> Void)
    
    /// Returns `TargetSearchResult` for the given search criteria.
    ///
    /// - Parameters:
    ///   - identifiers: Optional. The identifiers of the `PackageCollectionsModel.Collection`s  to search under.
    ///   - query: The search query expression
    ///   - type: The search type
    ///   - callback: The closure to invoke when result becomes available
    func searchTargets(identifiers: [Model.CollectionIdentifier]?,
                       query: String,
                       type: Model.TargetSearchType,
                       callback: @escaping (Result<Model.TargetSearchResult, Error>) -> Void)
}
