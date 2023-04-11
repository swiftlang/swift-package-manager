//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import PackageModel
import TSCBasic

// TODO: is there a better name? this conflicts with the module name which is okay in this case but not ideal in Swift
public struct PackageCollections: PackageCollectionsProtocol, Closable {
    // Check JSONPackageCollectionProvider.isSignatureCheckSupported before updating or removing this
    #if os(macOS) || os(Linux) || os(Windows) || os(Android)
    static let isSupportedPlatform = true
    #else
    static let isSupportedPlatform = false
    #endif

    let configuration: Configuration
    private let fileSystem: FileSystem
    private let observabilityScope: ObservabilityScope
    private let storageContainer: (storage: Storage, owned: Bool)
    private let collectionProviders: [Model.CollectionSourceType: PackageCollectionProvider]
    let metadataProvider: PackageMetadataProvider

    private var storage: Storage {
        self.storageContainer.storage
    }

    // initialize with defaults
    public init(
        configuration: Configuration = .init(),
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope
    ) {
        self.init(
            configuration: configuration,
            customMetadataProvider: nil,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope
        )
    }
    
    init(
        configuration: Configuration = .init(),
        customMetadataProvider: PackageMetadataProvider?,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope
    ) {
        let storage = Storage(
            sources: FilePackageCollectionsSourcesStorage(
                fileSystem: fileSystem,
                path: configuration.configurationDirectory?.appending("collections.json")
            ),
            collections: SQLitePackageCollectionsStorage(
                location: configuration.cacheDirectory.map { .path($0.appending(components: "package-collection.db")) },
                observabilityScope: observabilityScope
            )
        )

        let collectionProviders = [
            Model.CollectionSourceType.json: JSONPackageCollectionProvider(
                fileSystem: fileSystem,
                observabilityScope: observabilityScope
            )
        ]

        let metadataProvider = customMetadataProvider ?? GitHubPackageMetadataProvider(
            configuration: .init(
                authTokens: configuration.authTokens,
                cacheDir: configuration.cacheDirectory?.appending(components: "package-metadata")
            ),
            observabilityScope: observabilityScope
        )

        self.configuration = configuration
        self.fileSystem = fileSystem
        self.observabilityScope = observabilityScope
        self.storageContainer = (storage, true)
        self.collectionProviders = collectionProviders
        self.metadataProvider = metadataProvider
    }

    // internal initializer for testing
    init(configuration: Configuration = .init(),
         fileSystem: FileSystem,
         observabilityScope: ObservabilityScope,
         storage: Storage,
         collectionProviders: [Model.CollectionSourceType: PackageCollectionProvider],
         metadataProvider: PackageMetadataProvider
    ) {
        self.configuration = configuration
        self.fileSystem = fileSystem
        self.observabilityScope = observabilityScope
        self.storageContainer = (storage, false)
        self.collectionProviders = collectionProviders
        self.metadataProvider = metadataProvider
    }

    public func shutdown() throws {
        if self.storageContainer.owned {
            try self.storageContainer.storage.close()
        }
        
        if let metadataProvider = self.metadataProvider as? Closable {
            try metadataProvider.close()
        }
    }
    
    public func close() throws {
        try self.shutdown()
    }

    // MARK: - Collections

    public func listCollections(identifiers: Set<PackageCollectionsModel.CollectionIdentifier>? = nil,
                                callback: @escaping (Result<[PackageCollectionsModel.Collection], Error>) -> Void) {
        guard Self.isSupportedPlatform else {
            return callback(.failure(PackageCollectionError.unsupportedPlatform))
        }

        self.storage.sources.list { result in
            switch result {
            case .failure(let error):
                callback(.failure(error))
            case .success(let sources):
                let identiferSource = sources.reduce(into: [PackageCollectionsModel.CollectionIdentifier: PackageCollectionsModel.CollectionSource]()) { result, source in
                    result[.init(from: source)] = source
                }
                let identifiersToFetch = identiferSource.keys.filter { identifiers?.contains($0) ?? true }

                if identifiersToFetch.isEmpty {
                    return callback(.success([]))
                }

                self.storage.collections.list(identifiers: identifiersToFetch) { result in
                    switch result {
                    case .failure(let error):
                        callback(.failure(error))
                    case .success(var collections):
                        let sourceOrder = sources.enumerated().reduce(into: [Model.CollectionIdentifier: Int]()) { result, item in
                            result[.init(from: item.element)] = item.offset
                        }

                        // re-order by profile order which reflects the user's election
                        let sort = { (lhs: PackageCollectionsModel.Collection, rhs: PackageCollectionsModel.Collection) -> Bool in
                            sourceOrder[lhs.identifier] ?? 0 < sourceOrder[rhs.identifier] ?? 0
                        }

                        // We've fetched all the wanted collections and we're done
                        if collections.count == identifiersToFetch.count {
                            collections.sort(by: sort)
                            return callback(.success(collections))
                        }

                        // Some of the results are missing. This happens when deserialization of stored collections fail,
                        // so we will try refreshing the missing collections to update data in storage.
                        let missingSources = Set(identifiersToFetch.compactMap { identiferSource[$0] }).subtracting(Set(collections.map { $0.source }))
                        let refreshResults = ThreadSafeArrayStore<Result<Model.Collection, Error>>()
                        missingSources.forEach { source in
                            self.refreshCollectionFromSource(source: source, trustConfirmationProvider: nil) { refreshResult in
                                let count = refreshResults.append(refreshResult)
                                if count == missingSources.count {
                                    var result = collections + refreshResults.compactMap { $0.success } // best-effort; not returning errors
                                    result.sort(by: sort)
                                    callback(.success(result))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    public func refreshCollections(callback: @escaping (Result<[PackageCollectionsModel.CollectionSource], Error>) -> Void) {
        guard Self.isSupportedPlatform else {
            return callback(.failure(PackageCollectionError.unsupportedPlatform))
        }

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
                        let count = refreshResults.append(refreshResult)
                        if count == sources.count {
                            let errors = refreshResults.compactMap { $0.failure }
                            callback(errors.isEmpty ? .success(sources) : .failure(MultipleErrors(errors)))
                        }
                    }
                }
            }
        }
    }

    public func refreshCollection(_ source: PackageCollectionsModel.CollectionSource,
                                  callback: @escaping (Result<PackageCollectionsModel.Collection, Error>) -> Void) {
        guard Self.isSupportedPlatform else {
            return callback(.failure(PackageCollectionError.unsupportedPlatform))
        }

        self.storage.sources.list { result in
            switch result {
            case .failure(let error):
                callback(.failure(error))
            case .success(let sources):
                guard let savedSource = sources.first(where: { $0 == source }) else {
                    return callback(.failure(NotFoundError("\(source)")))
                }
                self.refreshCollectionFromSource(source: savedSource, trustConfirmationProvider: nil, callback: callback)
            }
        }
    }

    public func addCollection(_ source: PackageCollectionsModel.CollectionSource,
                              order: Int? = nil,
                              trustConfirmationProvider: ((PackageCollectionsModel.Collection, @escaping (Bool) -> Void) -> Void)? = nil,
                              callback: @escaping (Result<PackageCollectionsModel.Collection, Error>) -> Void) {
        guard Self.isSupportedPlatform else {
            return callback(.failure(PackageCollectionError.unsupportedPlatform))
        }

        if let errors = source.validate(fileSystem: self.fileSystem)?.errors() {
            return callback(.failure(MultipleErrors(errors)))
        }

        // first record the registration
        self.storage.sources.add(source: source, order: order) { result in
            switch result {
            case .failure(let error):
                callback(.failure(error))
            case .success:
                // next try to fetch the collection from the network and store it locally so future operations dont need to access the network
                self.refreshCollectionFromSource(source: source, trustConfirmationProvider: trustConfirmationProvider) { collectionResult in
                    switch collectionResult {
                    case .failure(let error):
                        // Don't delete the source if we are either pending user confirmation or have recorded user's preference.
                        // It is also possible that we can't verify signature (yet) due to config issue, which user can fix and we retry later.
                        if let error = error as? PackageCollectionError, error == .trustConfirmationRequired || error == .untrusted || error == .cannotVerifySignature {
                            return callback(.failure(error))
                        }
                        // Otherwise remove source since it fails to be fetched
                        self.storage.sources.remove(source: source) { _ in
                            // Whether removal succeeds or not, return the refresh error
                            callback(.failure(error))
                        }
                    case .success(let collection):
                        callback(.success(collection))
                    }
                }
            }
        }
    }

    public func removeCollection(_ source: PackageCollectionsModel.CollectionSource,
                                 callback: @escaping (Result<Void, Error>) -> Void) {
        guard Self.isSupportedPlatform else {
            return callback(.failure(PackageCollectionError.unsupportedPlatform))
        }

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
        guard Self.isSupportedPlatform else {
            return callback(.failure(PackageCollectionError.unsupportedPlatform))
        }

        self.storage.sources.move(source: source, to: order, callback: callback)
    }

    public func updateCollection(_ source: PackageCollectionsModel.CollectionSource,
                                 callback: @escaping (Result<PackageCollectionsModel.Collection, Error>) -> Void) {
        guard Self.isSupportedPlatform else {
            return callback(.failure(PackageCollectionError.unsupportedPlatform))
        }

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
        guard Self.isSupportedPlatform else {
            return callback(.failure(PackageCollectionError.unsupportedPlatform))
        }

        self.storage.collections.get(identifier: .init(from: source)) { result in
            switch result {
            case .failure:
                // The collection is not in storage. Validate the source before fetching it.
                if let errors = source.validate(fileSystem: self.fileSystem)?.errors() {
                    return callback(.failure(MultipleErrors(errors)))
                }
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

    public func findPackages(_ query: String,
                             collections: Set<PackageCollectionsModel.CollectionIdentifier>? = nil,
                             callback: @escaping (Result<PackageCollectionsModel.PackageSearchResult, Error>) -> Void) {
        guard Self.isSupportedPlatform else {
            return callback(.failure(PackageCollectionError.unsupportedPlatform))
        }

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

    public func listPackages(collections: Set<PackageCollectionsModel.CollectionIdentifier>? = nil,
                             callback: @escaping (Result<PackageCollectionsModel.PackageSearchResult, Error>) -> Void) {
        self.listCollections(identifiers: collections) { result in
            switch result {
            case .failure(let error):
                callback(.failure(error))
            case .success(let collections):
                var packageCollections = [PackageIdentity: (package: Model.Package, collections: Set<Model.CollectionIdentifier>)]()
                // Use package data from the most recently processed collection
                collections.sorted(by: { $0.lastProcessedAt > $1.lastProcessedAt }).forEach { collection in
                    collection.packages.forEach { package in
                        var entry = packageCollections.removeValue(forKey: package.identity)
                        if entry == nil {
                            entry = (package, .init())
                        }

                        if var entry = entry {
                            entry.collections.insert(collection.identifier)
                            packageCollections[package.identity] = entry
                        }
                    }
                }

                let result = PackageCollectionsModel.PackageSearchResult(
                    items: packageCollections.sorted { $0.value.package.displayName < $1.value.package.displayName }
                        .map { entry in
                        .init(package: entry.value.package, collections: Array(entry.value.collections))
                        }
                )
                callback(.success(result))
            }
        }
    }

    // MARK: - Package Metadata

    public func getPackageMetadata(identity: PackageIdentity,
                                   location: String? = .none,
                                   callback: @escaping (Result<PackageCollectionsModel.PackageMetadata, Error>) -> Void) {
        self.getPackageMetadata(identity: identity, location: location, collections: .none, callback: callback)
    }

    public func getPackageMetadata(identity: PackageIdentity,
                                   location: String? = .none,
                                   collections: Set<PackageCollectionsModel.CollectionIdentifier>?,
                                   callback: @escaping (Result<PackageCollectionsModel.PackageMetadata, Error>) -> Void) {
        guard Self.isSupportedPlatform else {
            return callback(.failure(PackageCollectionError.unsupportedPlatform))
        }

        // first find in storage
        self.findPackage(identity: identity, location: location, collections: collections) { result in
            switch result {
            case .failure(let error):
                callback(.failure(error))
            case .success(let packageSearchResult):
                // then try to get more metadata from provider (optional)
                self.metadataProvider.get(identity: packageSearchResult.package.identity, location: packageSearchResult.package.location) { result, provider in
                    switch result {
                    case .failure(let error):
                        self.observabilityScope.emit(warning: "Failed fetching information about \(identity) from \(self.metadataProvider.self): \(error)")
                        let metadata = Model.PackageMetadata(
                            package: Self.mergedPackageMetadata(package: packageSearchResult.package, basicMetadata: nil),
                            collections: packageSearchResult.collections,
                            provider: provider
                        )
                        callback(.success(metadata))
                    case .success(let basicMetadata):
                        // finally merge the results
                        let metadata = Model.PackageMetadata(
                            package: Self.mergedPackageMetadata(package: packageSearchResult.package, basicMetadata: basicMetadata),
                            collections: packageSearchResult.collections,
                            provider: provider
                        )
                        callback(.success(metadata))
                    }
                }
            }
        }
    }

    // MARK: - Targets

    public func listTargets(collections: Set<PackageCollectionsModel.CollectionIdentifier>? = nil,
                            callback: @escaping (Result<PackageCollectionsModel.TargetListResult, Error>) -> Void) {
        guard Self.isSupportedPlatform else {
            return callback(.failure(PackageCollectionError.unsupportedPlatform))
        }

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

    public func findTargets(_ query: String,
                            searchType: PackageCollectionsModel.TargetSearchType? = nil,
                            collections: Set<PackageCollectionsModel.CollectionIdentifier>? = nil,
                            callback: @escaping (Result<PackageCollectionsModel.TargetSearchResult, Error>) -> Void) {
        guard Self.isSupportedPlatform else {
            return callback(.failure(PackageCollectionError.unsupportedPlatform))
        }

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
        guard let provider = self.collectionProviders[source.type] else {
            return callback(.failure(UnknownProvider(source.type)))
        }
        provider.get(source) { result in
            switch result {
            case .failure(let error):
                // Remove the unavailable/invalid collection (if previously saved) from storage before calling back
                self.storage.collections.remove(identifier: PackageCollectionsModel.CollectionIdentifier(from: source)) { _ in
                    callback(.failure(error))
                }
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
                                var collection = collection
                                collection.source = source
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

    func findPackage(identity: PackageIdentity,
                     location: String?,
                     collections: Set<PackageCollectionsModel.CollectionIdentifier>?,
                     callback: @escaping (Result<PackageCollectionsModel.PackageSearchResult.Item, Error>) -> Void) {
        self.storage.sources.list { result in
            let notFoundError = NotFoundError("identity: \(identity), location: \(location ?? "none")")
            
            switch result {
            case .failure(is NotFoundError):
                callback(.failure(notFoundError))
            case .failure(let error):
                callback(.failure(error))
            case .success(let sources):
                var collectionIdentifiers = sources.map { Model.CollectionIdentifier(from: $0) }
                if let collections {
                    collectionIdentifiers = collectionIdentifiers.filter { collections.contains($0) }
                }
                if collectionIdentifiers.isEmpty {
                    return callback(.failure(notFoundError))
                }
                self.storage.collections.findPackage(identifier: identity, collectionIdentifiers: collectionIdentifiers) { findPackageResult in
                    switch findPackageResult {
                    case .failure(is NotFoundError):
                        callback(.failure(notFoundError))
                    case .failure(let error):
                        callback(.failure(error))
                    case .success(let packagesCollections):
                        let matches: [PackageCollectionsModel.Package]
                        if let location {
                            // A package identity can be associated with multiple repository URLs
                            matches = packagesCollections.packages.filter { CanonicalPackageLocation($0.location) == CanonicalPackageLocation(location) }
                        }
                        else {
                            matches = packagesCollections.packages
                        }
                        guard let package = matches.first else {
                            return callback(.failure(notFoundError))
                        }
                        callback(.success(.init(package: package, collections: packagesCollections.collections)))
                    }
                }
            }
        }
    }

    private func targetListResultFromCollections(_ collections: [Model.Collection]) -> Model.TargetListResult {
        var packageCollections = [PackageIdentity: (package: Model.Package, collections: Set<Model.CollectionIdentifier>)]()
        var targetsPackages = [String: (target: Model.Target, packages: Set<PackageIdentity>)]()

        collections.forEach { collection in
            collection.packages.forEach { package in
                // Avoid copy-on-write: remove entry from dictionary before mutating
                var entry = packageCollections.removeValue(forKey: package.identity) ?? (package, .init())
                entry.collections.insert(collection.identifier)
                packageCollections[package.identity] = entry

                package.versions.forEach { version in
                    version.manifests.values.forEach { manifest in
                        manifest.targets.forEach { target in
                            // Avoid copy-on-write: remove entry from dictionary before mutating
                            var entry = targetsPackages.removeValue(forKey: target.name) ?? (target: target, packages: .init())
                            entry.packages.insert(package.identity)
                            targetsPackages[target.name] = entry
                        }
                    }
                }
            }
        }

        return targetsPackages.map { _, pair in
            let targetPackages = pair.packages
                .compactMap { packageCollections[$0] }
                .map { pair -> Model.TargetListResult.Package in
                    let versions = pair.package.versions.flatMap { version in
                        version.manifests.values.map { manifest in
                            Model.TargetListResult.PackageVersion(
                                version: version.version,
                                toolsVersion: manifest.toolsVersion,
                                packageName: manifest.packageName
                            )
                        }
                    }
                    return .init(identity: pair.package.identity,
                                 location: pair.package.location,
                                 summary: pair.package.summary,
                                 versions: versions,
                                 collections: Array(pair.collections))
                }

            return Model.TargetListItem(target: pair.target, packages: targetPackages)
        }
    }

    internal static func mergedPackageMetadata(package: Model.Package,
                                               basicMetadata: Model.PackageBasicMetadata?) -> Model.Package {
        // This dictionary contains recent releases and might not contain everything that's in package.versions.
        let basicVersionMetadata = basicMetadata.map { Dictionary($0.versions.map { ($0.version, $0) }, uniquingKeysWith: { first, _ in first }) } ?? [:]
        var versions = package.versions.map { packageVersion -> Model.Package.Version in
            let versionMetadata = basicVersionMetadata[packageVersion.version]
            return .init(version: packageVersion.version,
                         title: versionMetadata?.title ?? packageVersion.title,
                         summary: versionMetadata?.summary ?? packageVersion.summary,
                         manifests: packageVersion.manifests,
                         defaultToolsVersion: packageVersion.defaultToolsVersion,
                         verifiedCompatibility: packageVersion.verifiedCompatibility,
                         license: packageVersion.license,
                         author: versionMetadata?.author,
                         createdAt: versionMetadata?.createdAt ?? packageVersion.createdAt)
        }
        versions.sort(by: >)

        return Model.Package(
            identity: package.identity,
            location: package.location,
            summary: basicMetadata?.summary ?? package.summary,
            keywords: basicMetadata?.keywords ?? package.keywords,
            versions: versions,
            watchersCount: basicMetadata?.watchersCount,
            readmeURL: basicMetadata?.readmeURL ?? package.readmeURL,
            license: basicMetadata?.license ?? package.license,
            authors: basicMetadata?.authors ?? package.authors,
            languages: basicMetadata?.languages ?? package.languages
        )
    }
}

private struct UnknownProvider: Error {
    let sourceType: Model.CollectionSourceType

    init(_ sourceType: Model.CollectionSourceType) {
        self.sourceType = sourceType
    }
}
