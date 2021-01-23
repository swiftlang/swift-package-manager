/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020-2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import PackageModel
import TSCBasic

// TODO: is there a better name? this conflicts with the module name which is okay in this case but not ideal in Swift
public struct PackageCollections: PackageCollectionsProtocol {
    private let configuration: Configuration
    private let diagnosticsEngine: DiagnosticsEngine?
    private let storageContainer: (storage: Storage, owned: Bool)
    private let collectionProviders: [Model.CollectionSourceType: PackageCollectionProvider]
    private let metadataProvider: PackageMetadataProvider

    private var storage: Storage {
        self.storageContainer.storage
    }

    // initialize with defaults
    public init(configuration: Configuration = .init(), diagnosticsEngine: DiagnosticsEngine? = nil) {
        let storage = Storage(sources: FilePackageCollectionsSourcesStorage(diagnosticsEngine: diagnosticsEngine),
                              collections: SQLitePackageCollectionsStorage(diagnosticsEngine: diagnosticsEngine))

        let collectionProviders = [Model.CollectionSourceType.json: JSONPackageCollectionProvider(diagnosticsEngine: diagnosticsEngine)]

        let metadataProvider = GitHubPackageMetadataProvider(configuration: .init(authTokens: configuration.authTokens),
                                                             diagnosticsEngine: diagnosticsEngine)

        self.configuration = configuration
        self.diagnosticsEngine = diagnosticsEngine
        self.storageContainer = (storage, true)
        self.collectionProviders = collectionProviders
        self.metadataProvider = metadataProvider
    }

    // internal initializer for testing
    init(configuration: Configuration = .init(),
         diagnosticsEngine: DiagnosticsEngine? = nil,
         storage: Storage,
         collectionProviders: [Model.CollectionSourceType: PackageCollectionProvider],
         metadataProvider: PackageMetadataProvider) {
        self.configuration = configuration
        self.diagnosticsEngine = diagnosticsEngine
        self.storageContainer = (storage, false)
        self.collectionProviders = collectionProviders
        self.metadataProvider = metadataProvider
    }

    public func shutdown() throws {
        if self.storageContainer.owned {
            try self.storageContainer.storage.close()
        }
    }

    // MARK: - Collections

    public func listCollections(identifiers: Set<PackageCollectionsModel.CollectionIdentifier>? = nil,
                                callback: @escaping (Result<[PackageCollectionsModel.Collection], Error>) -> Void) {
        self.storage.sources.list { result in
            switch result {
            case .failure(let error):
                callback(.failure(error))
            case .success(let sources):
                let identifiers = sources.map { .init(from: $0) }.filter { identifiers?.contains($0) ?? true }
                if identifiers.isEmpty {
                    return callback(.success([]))
                }
                let collectionOrder = identifiers.enumerated().reduce([Model.CollectionIdentifier: Int]()) { partial, element in
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

    public func refreshCollections(callback: @escaping (Result<[PackageCollectionsModel.CollectionSource], Error>) -> Void) {
        self.storage.sources.list { result in
            switch result {
            case .failure(let error):
                callback(.failure(error))
            case .success(let sources):
                if sources.isEmpty {
                    return callback(.success([]))
                }
                let refreshResults = ThreadSafeArrayStore<Result<Model.Collection, Error>>()
                sources.forEach { source in
                    self.refreshCollectionFromSource(source: source, trustConfirmationProvider: nil) { refreshResult in
                        refreshResults.append(refreshResult)
                        if refreshResults.count == sources.count {
                            let errors = refreshResults.compactMap { $0.failure }
                            callback(errors.isEmpty ? .success(sources) : .failure(MultipleErrors(errors)))
                        }
                    }
                }
            }
        }
    }

    public func refreshCollection(
        _ source: PackageCollectionsModel.CollectionSource,
        callback: @escaping (Result<PackageCollectionsModel.Collection, Error>) -> Void
    ) {
        self.refreshCollectionFromSource(source: source, trustConfirmationProvider: nil, callback: callback)
    }

    public func addCollection(_ source: PackageCollectionsModel.CollectionSource,
                              order: Int? = nil,
                              trustConfirmationProvider: ((PackageCollectionsModel.Collection, @escaping (Bool) -> Void) -> Void)? = nil,
                              callback: @escaping (Result<PackageCollectionsModel.Collection, Error>) -> Void) {
        if let errors = source.validate()?.errors() {
            return callback(.failure(MultipleErrors(errors)))
        }

        // first record the registration
        self.storage.sources.add(source: source, order: order) { result in
            switch result {
            case .failure(let error):
                callback(.failure(error))
            case .success:
                // next try to fetch the collection from the network and store it locally so future operations dont need to access the network
                self.refreshCollectionFromSource(source: source, trustConfirmationProvider: trustConfirmationProvider, callback: callback)
            }
        }
    }

    public func removeCollection(_ source: PackageCollectionsModel.CollectionSource,
                                 callback: @escaping (Result<Void, Error>) -> Void) {
        self.storage.sources.remove(source: source) { result in
            switch result {
            case .failure(let error):
                callback(.failure(error))
            case .success:
                self.storage.collections.remove(identifier: .init(from: source), callback: callback)
            }
        }
    }

    public func moveCollection(_ source: PackageCollectionsModel.CollectionSource,
                               to order: Int,
                               callback: @escaping (Result<Void, Error>) -> Void) {
        self.storage.sources.move(source: source, to: order, callback: callback)
    }

    public func updateCollection(_ source: PackageCollectionsModel.CollectionSource,
                                 callback: @escaping (Result<PackageCollectionsModel.Collection, Error>) -> Void) {
        self.storage.sources.update(source: source) { result in
            switch result {
            case .failure(let error):
                callback(.failure(error))
            case .success:
                self.refreshCollectionFromSource(source: source, trustConfirmationProvider: nil, callback: callback)
            }
        }
    }

    // Returns information about a package collection.
    // The collection is not required to be in the configured list.
    // If not found locally (storage), the collection will be fetched from the source.
    public func getCollection(_ source: PackageCollectionsModel.CollectionSource,
                              callback: @escaping (Result<PackageCollectionsModel.Collection, Error>) -> Void) {
        if let errors = source.validate()?.errors() {
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
        callback: @escaping (Result<PackageCollectionsModel.PackageSearchResult, Error>) -> Void
    ) {
        self.storage.sources.list { result in
            switch result {
            case .failure(let error):
                callback(.failure(error))
            case .success(let sources):
                let identifiers = sources.map { .init(from: $0) }.filter { collections?.contains($0) ?? true }
                if identifiers.isEmpty {
                    return callback(.success(Model.PackageSearchResult(items: [])))
                }
                self.storage.collections.searchPackages(identifiers: identifiers, query: query, callback: callback)
            }
        }
    }

    // MARK: - Package Metadata

    public func getPackageMetadata(_ reference: PackageReference,
                                   callback: @escaping (Result<PackageCollectionsModel.PackageMetadata, Error>) -> Void) {
        // first find in storage
        self.findPackage(identifier: reference.identity) { result in
            switch result {
            case .failure(let error):
                callback(.failure(error))
            case .success(let packageSearchResult):
                // then try to get more metadata from provider (optional)
                self.metadataProvider.get(reference) { result in
                    switch result {
                    case .failure(let error) where error is NotFoundError:
                        self.diagnosticsEngine?.emit(warning: "Failed fetching information about \(reference) from \(self.metadataProvider.name).")
                        let metadata = Model.PackageMetadata(
                            package: Self.mergedPackageMetadata(package: packageSearchResult.package, basicMetadata: nil),
                            collections: packageSearchResult.collections
                        )
                        callback(.success(metadata))
                    case .failure(let error):
                        self.diagnosticsEngine?.emit(error: "Failed fetching information about \(reference) from \(self.metadataProvider.name).")
                        callback(.failure(error))
                    case .success(let basicMetadata):
                        // finally merge the results
                        let metadata = Model.PackageMetadata(
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
        callback: @escaping (Result<PackageCollectionsModel.TargetListResult, Error>) -> Void
    ) {
        self.listCollections(identifiers: collections) { result in
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
        callback: @escaping (Result<PackageCollectionsModel.TargetSearchResult, Error>) -> Void
    ) {
        let searchType = searchType ?? .exactMatch

        self.storage.sources.list { result in
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
                                             trustConfirmationProvider: ((PackageCollectionsModel.Collection, @escaping (Bool) -> Void) -> Void)?,
                                             callback: @escaping (Result<Model.Collection, Error>) -> Void) {
        if let errors = source.validate()?.errors() {
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
                // If collection is signed and signature is valid, save to storage. `provider.get`
                // would have failed if signature were invalid.
                if collection.isSigned {
                    return self.storage.collections.put(collection: collection, callback: callback)
                }

                // If collection is not signed, check if it's trusted by user and prompt user if needed.
                if let isTrusted = source.isTrusted {
                    if isTrusted {
                        return self.storage.collections.put(collection: collection, callback: callback)
                    } else {
                        // Try to remove the untrusted collection (if previously saved) from storage before calling back
                        return self.storage.collections.remove(identifier: collection.identifier) { _ in
                            callback(.failure(PackageCollectionError.untrusted))
                        }
                    }
                }

                // No user preference recorded, so we need to prompt if we can.
                guard let trustConfirmationProvider = trustConfirmationProvider else {
                    // Try to remove the untrusted collection (if previously saved) from storage before calling back
                    return self.storage.collections.remove(identifier: collection.identifier) { _ in
                        callback(.failure(PackageCollectionError.trustConfirmationRequired))
                    }
                }

                trustConfirmationProvider(collection) { userTrusted in
                    var source = source
                    source.isTrusted = userTrusted
                    // Record user preference then save collection to storage
                    self.storage.sources.update(source: source) { updateSourceResult in
                        switch updateSourceResult {
                        case .failure(let error):
                            callback(.failure(error))
                        case .success:
                            if userTrusted {
                                self.storage.collections.put(collection: collection, callback: callback)
                            } else {
                                // Try to remove the untrusted collection (if previously saved) from storage before calling back
                                return self.storage.collections.remove(identifier: collection.identifier) { _ in
                                    callback(.failure(PackageCollectionError.untrusted))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func findPackage(
        identifier: PackageIdentity,
        callback: @escaping (Result<PackageCollectionsModel.PackageSearchResult.Item, Error>) -> Void
    ) {
        self.storage.sources.list { result in
            switch result {
            case .failure(let error):
                callback(.failure(error))
            case .success(let sources):
                let identifiers = sources.map { Model.CollectionIdentifier(from: $0) }
                if identifiers.isEmpty {
                    return callback(.failure(NotFoundError("\(identifier)")))
                }
                self.storage.collections.findPackage(identifier: identifier, collectionIdentifiers: identifiers, callback: callback)
            }
        }
    }

    private func targetListResultFromCollections(_ collections: [Model.Collection]) -> Model.TargetListResult {
        var packageCollections = [PackageReference: (package: Model.Package, collections: Set<Model.CollectionIdentifier>)]()
        var targetsPackages = [String: (target: Model.Target, packages: Set<PackageReference>)]()

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
                .map { pair -> Model.TargetListResult.Package in
                    let versions = pair.package.versions.map { Model.TargetListResult.PackageVersion(version: $0.version, packageName: $0.packageName) }
                    return .init(repository: pair.package.repository,
                                 summary: pair.package.summary,
                                 versions: versions,
                                 collections: Array(pair.collections))
                }

            return Model.TargetListItem(target: pair.target, packages: targetPackages)
        }
    }

    internal static func mergedPackageMetadata(package: Model.Package,
                                               basicMetadata: Model.PackageBasicMetadata?) -> Model.Package {
        var versions = package.versions.map { packageVersion -> Model.Package.Version in
            .init(version: packageVersion.version,
                  packageName: packageVersion.packageName,
                  targets: packageVersion.targets,
                  products: packageVersion.products,
                  toolsVersion: packageVersion.toolsVersion,
                  minimumPlatformVersions: packageVersion.minimumPlatformVersions,
                  verifiedCompatibility: packageVersion.verifiedCompatibility,
                  license: packageVersion.license)
        }
        versions.sort(by: >)

        return Model.Package(
            repository: package.repository,
            summary: basicMetadata?.summary ?? package.summary,
            keywords: basicMetadata?.keywords ?? package.keywords,
            versions: versions,
            watchersCount: basicMetadata?.watchersCount,
            readmeURL: basicMetadata?.readmeURL ?? package.readmeURL,
            license: basicMetadata?.license ?? package.license,
            authors: basicMetadata?.authors
        )
    }
}

private struct UnknownProvider: Error {
    let sourceType: Model.CollectionSourceType

    init(_ sourceType: Model.CollectionSourceType) {
        self.sourceType = sourceType
    }
}
