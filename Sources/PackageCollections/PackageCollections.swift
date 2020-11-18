/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import PackageModel
import TSCBasic

// TODO: is there a better name? this conflicts with the module name which is okay in this case but not ideal in Swift
public struct PackageCollections: PackageCollectionsProtocol {
    private let configuration: Configuration
    private let storage: Storage
    private let collectionProviders: [PackageCollectionsModel.CollectionSourceType: PackageCollectionProvider]
    private let metadataProvider: PackageMetadataProvider

    init(configuration: Configuration,
         storage: Storage,
         collectionProviders: [PackageCollectionsModel.CollectionSourceType: PackageCollectionProvider],
         metadataProvider: PackageMetadataProvider) {
        self.configuration = configuration
        self.storage = storage
        self.collectionProviders = collectionProviders
        self.metadataProvider = metadataProvider
    }

    // MARK: - Profiles

    public func listProfiles(callback: @escaping (Result<[PackageCollectionsModel.Profile], Error>) -> Void) {
        self.storage.collectionsProfiles.listProfiles(callback: callback)
    }

    // MARK: - Collections

    public func listCollections(identifiers: Set<PackageCollectionsModel.CollectionIdentifier>? = nil,
                                in profile: PackageCollectionsModel.Profile? = nil,
                                callback: @escaping (Result<[PackageCollectionsModel.Collection], Error>) -> Void) {
        let profile = profile ?? .default

        self.storage.collectionsProfiles.listSources(in: profile) { result in
            switch result {
            case .failure(let error):
                callback(.failure(error))
            case .success(let sources):
                let identifiers = sources.map { .init(from: $0) }.filter { identifiers?.contains($0) ?? true }
                if identifiers.isEmpty {
                    return callback(.success([]))
                }
                let collectionOrder = identifiers.enumerated().reduce([PackageCollectionsModel.CollectionIdentifier: Int]()) { partial, element in
                    var dictionary = partial
                    dictionary[element.element] = element.offset
                    return dictionary
                }
                self.storage.collections.list(identifiers: identifiers) { result in
                    switch result {
                    case .failure(let error):
                        callback(.failure(error))
                    case .success(var collections):
                        // re-order by profile order which reflects the user's election
                        collections.sort(by: { lhs, rhs in collectionOrder[lhs.identifier] ?? 0 < collectionOrder[rhs.identifier] ?? 0 })
                        callback(.success(collections))
                    }
                }
            }
        }
    }

    public func refreshCollections(in profile: PackageCollectionsModel.Profile? = nil,
                                   callback: @escaping (Result<[PackageCollectionsModel.CollectionSource], Error>) -> Void) {
        let profile = profile ?? .default

        self.storage.collectionsProfiles.listSources(in: profile) { result in
            switch result {
            case .failure(let error):
                callback(.failure(error))
            case .success(let sources):
                if sources.isEmpty {
                    return callback(.success([]))
                }
                let lock = Lock()
                var refreshResults = [Result<PackageCollectionsModel.Collection, Error>]()
                sources.forEach { source in
                    self.refreshCollectionFromSource(source: source, profile: profile) { refreshResult in
                        lock.withLock { refreshResults.append(refreshResult) }
                        if refreshResults.count == (lock.withLock { sources.count }) {
                            let errors = refreshResults.compactMap { $0.failure }
                            callback(errors.isEmpty ? .success(sources) : .failure(MultipleErrors(errors)))
                        }
                    }
                }
            }
        }
    }

    public func addCollection(_ source: PackageCollectionsModel.CollectionSource,
                              order: Int? = nil,
                              to profile: PackageCollectionsModel.Profile? = nil,
                              callback: @escaping (Result<PackageCollectionsModel.Collection, Error>) -> Void) {
        let profile = profile ?? .default

        if let errors = source.validate() {
            return callback(.failure(MultipleErrors(errors)))
        }

        // first record the registration
        self.storage.collectionsProfiles.add(source: source, order: order, to: profile) { result in
            switch result {
            case .failure(let error):
                callback(.failure(error))
            case .success:
                // next try to fetch the collection from the network and store it locally so future operations dont need to access the network
                self.refreshCollectionFromSource(source: source, order: order, profile: profile, callback: callback)
            }
        }
    }

    public func removeCollection(_ source: PackageCollectionsModel.CollectionSource,
                                 from profile: PackageCollectionsModel.Profile? = nil,
                                 callback: @escaping (Result<Void, Error>) -> Void) {
        let profile = profile ?? .default

        self.storage.collectionsProfiles.remove(source: source, from: profile) { result in
            switch result {
            case .failure(let error):
                callback(.failure(error))
            case .success:
                // check to see if the collection is used in some other profile,
                // if not delete it from storage to reduce disk space
                self.storage.collectionsProfiles.exists(source: source, in: nil) { result in
                    switch result {
                    case .failure(let error):
                        callback(.failure(error))
                    case .success(let exists):
                        if exists {
                            callback(.success(()))
                        } else {
                            self.storage.collections.remove(identifier: .init(from: source), callback: callback)
                        }
                    }
                }
            }
        }
    }

    public func moveCollection(_ source: PackageCollectionsModel.CollectionSource,
                               to order: Int, in profile: PackageCollectionsModel.Profile? = nil,
                               callback: @escaping (Result<Void, Error>) -> Void) {
        let profile = profile ?? .default

        self.storage.collectionsProfiles.move(source: source, to: order, in: profile, callback: callback)
    }

    // Returns information about a package collection.
    // The collection is not required to be in the configured list.
    // If not found locally (storage), the collection will be fetched from the source.
    public func getCollection(_ source: PackageCollectionsModel.CollectionSource,
                              callback: @escaping (Result<PackageCollectionsModel.Collection, Error>) -> Void) {
        if let errors = source.validate() {
            return callback(.failure(MultipleErrors(errors)))
        }

        self.storage.collections.get(identifier: .init(from: source)) { result in
            switch result {
            case .failure:
                guard let provider = self.collectionProviders[source.type] else {
                    return callback(.failure(UnknownProvider(source.type)))
                }
                provider.get(source, callback: callback)
            case .success(let collection):
                callback(.success(collection))
            }
        }
    }

    // MARK: - Packages

    public func findPackages(
        _ query: String,
        collections: Set<PackageCollectionsModel.CollectionIdentifier>? = nil,
        profile: PackageCollectionsModel.Profile? = nil,
        callback: @escaping (Result<PackageCollectionsModel.PackageSearchResult, Error>) -> Void
    ) {
        let profile = profile ?? .default

        self.storage.collectionsProfiles.listSources(in: profile) { result in
            switch result {
            case .failure(let error):
                callback(.failure(error))
            case .success(let sources):
                let identifiers = sources.map { .init(from: $0) }.filter { collections?.contains($0) ?? true }
                if identifiers.isEmpty {
                    return callback(.success(PackageCollectionsModel.PackageSearchResult(items: [])))
                }
                self.storage.collections.searchPackages(identifiers: identifiers, query: query, callback: callback)
            }
        }
    }

    // MARK: - Package Metadata

    public func getPackageMetadata(_ reference: PackageReference,
                                   profile: PackageCollectionsModel.Profile? = nil,
                                   callback: @escaping (Result<PackageCollectionsModel.PackageMetadata, Error>) -> Void) {
        let profile = profile ?? .default

        // first find in storage
        self.findPackage(identifier: reference.identity, profile: profile) { result in
            switch result {
            case .failure(let error):
                callback(.failure(error))
            case .success(let packageSearchResult):
                // then try to get more metadata from provider (optional)
                self.metadataProvider.get(reference: reference) { result in
                    switch result {
                    case .failure(let error):
                        callback(.failure(error))
                    case .success(let basicMetadata):
                        // finally merge the results
                        let metadata = PackageCollectionsModel.PackageMetadata(
                            package: Self.mergedPackageMetadata(package: packageSearchResult.package, basicMetadata: basicMetadata),
                            collections: packageSearchResult.collections
                        )
                        callback(.success(metadata))
                    }
                }
            }
        }
    }

    // MARK: - Targets

    public func listTargets(
        collections: Set<PackageCollectionsModel.CollectionIdentifier>? = nil,
        in profile: PackageCollectionsModel.Profile? = nil,
        callback: @escaping (Result<PackageCollectionsModel.TargetListResult, Error>) -> Void
    ) {
        self.listCollections(identifiers: collections, in: profile) { result in
            switch result {
            case .failure(let error):
                callback(.failure(error))
            case .success(let collections):
                let targets = self.targetListResultFromCollections(collections)
                callback(.success(targets))
            }
        }
    }

    public func findTargets(
        _ query: String,
        searchType: PackageCollectionsModel.TargetSearchType? = nil,
        collections: Set<PackageCollectionsModel.CollectionIdentifier>? = nil,
        profile: PackageCollectionsModel.Profile? = nil,
        callback: @escaping (Result<PackageCollectionsModel.TargetSearchResult, Error>) -> Void
    ) {
        let profile = profile ?? .default
        let searchType = searchType ?? .exactMatch

        self.storage.collectionsProfiles.listSources(in: profile) { result in
            switch result {
            case .failure(let error):
                callback(.failure(error))
            case .success(let sources):
                let identifiers = sources.map { .init(from: $0) }.filter { collections?.contains($0) ?? true }
                if identifiers.isEmpty {
                    return callback(.success(.init(items: [])))
                }
                self.storage.collections.searchTargets(identifiers: identifiers, query: query, type: searchType, callback: callback)
            }
        }
    }

    // MARK: - Private

    // Fetch the collection from the network and store it in local storage
    // This helps avoid network access in normal operations
    private func refreshCollectionFromSource(source: PackageCollectionsModel.CollectionSource,
                                             order _: Int? = nil,
                                             profile _: PackageCollectionsModel.Profile? = nil,
                                             callback: @escaping (Result<PackageCollectionsModel.Collection, Error>) -> Void) {
        if let errors = source.validate() {
            return callback(.failure(MultipleErrors(errors)))
        }
        guard let provider = self.collectionProviders[source.type] else {
            return callback(.failure(UnknownProvider(source.type)))
        }
        provider.get(source) { result in
            switch result {
            case .failure(let error):
                callback(.failure(error))
            case .success(let collection):
                self.storage.collections.put(collection: collection, callback: callback)
            }
        }
    }

    func findPackage(
        identifier: PackageIdentity,
        profile: PackageCollectionsModel.Profile? = nil,
        callback: @escaping (Result<PackageCollectionsModel.PackageSearchResult.Item, Error>) -> Void
    ) {
        let profile = profile ?? .default

        self.storage.collectionsProfiles.listSources(in: profile) { result in
            switch result {
            case .failure(let error):
                callback(.failure(error))
            case .success(let sources):
                let identifiers = sources.map { PackageCollectionsModel.CollectionIdentifier(from: $0) }
                if identifiers.isEmpty {
                    return callback(.failure(NotFoundError("\(identifier)")))
                }
                self.storage.collections.findPackage(identifier: identifier, collectionIdentifiers: identifiers, callback: callback)
            }
        }
    }

    private func targetListResultFromCollections(_ collections: [PackageCollectionsModel.Collection]) -> PackageCollectionsModel.TargetListResult {
        var packageCollections = [PackageReference: (package: PackageCollectionsModel.Collection.Package, collections: Set<PackageCollectionsModel.CollectionIdentifier>)]()
        var targetsPackages = [String: (target: PackageCollectionsModel.PackageTarget, packages: Set<PackageReference>)]()

        collections.forEach { collection in
            collection.packages.forEach { package in
                // Avoid copy-on-write: remove entry from dictionary before mutating
                var entry = packageCollections.removeValue(forKey: package.reference) ?? (package, .init())
                entry.collections.insert(collection.identifier)
                packageCollections[package.reference] = entry

                package.versions.forEach { version in
                    version.targets.forEach { target in
                        // Avoid copy-on-write: remove entry from dictionary before mutating
                        var entry = targetsPackages.removeValue(forKey: target.name) ?? (target: target, packages: .init())
                        entry.packages.insert(package.reference)
                        targetsPackages[target.name] = entry
                    }
                }
            }
        }

        return targetsPackages.map { _, pair in
            let targetPackages = pair.packages
                .compactMap { packageCollections[$0] }
                .map { pair -> PackageCollectionsModel.TargetListResult.Package in
                    let versions = pair.package.versions.map { PackageCollectionsModel.TargetListResult.PackageVersion(version: $0.version, packageName: $0.packageName) }
                    return .init(repository: pair.package.repository,
                                 description: pair.package.summary,
                                 versions: versions,
                                 collections: Array(pair.collections))
                }

            return PackageCollectionsModel.TargetListItem(target: pair.target, packages: targetPackages)
        }
    }

    internal static func mergedPackageMetadata(package: PackageCollectionsModel.Collection.Package,
                                               basicMetadata: PackageCollectionsModel.PackageBasicMetadata?) -> PackageCollectionsModel.Package {
        var versions = package.versions.map { packageVersion -> PackageCollectionsModel.Package.Version in
            .init(version: packageVersion.version,
                  packageName: packageVersion.packageName,
                  targets: packageVersion.targets,
                  products: packageVersion.products,
                  toolsVersion: packageVersion.toolsVersion,
                  verifiedPlatforms: packageVersion.verifiedPlatforms,
                  verifiedSwiftVersions: packageVersion.verifiedSwiftVersions,
                  license: packageVersion.license)
        }

        // uses TSCUtility.Version comparator
        versions.sort(by: { lhs, rhs in lhs.version > rhs.version })
        let latestVersion = versions.first

        return .init(
            repository: package.repository,
            description: basicMetadata?.description ?? package.summary,
            versions: versions,
            latestVersion: latestVersion,
            watchersCount: basicMetadata?.watchersCount,
            readmeURL: basicMetadata?.readmeURL ?? package.readmeURL,
            authors: basicMetadata?.authors
        )
    }
}

private struct UnknownProvider: Error {
    let sourceType: PackageCollectionsModel.CollectionSourceType

    init(_ sourceType: PackageCollectionsModel.CollectionSourceType) {
        self.sourceType = sourceType
    }
}
