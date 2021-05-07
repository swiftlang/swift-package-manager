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
    // Check JSONPackageCollectionProvider.isSignatureCheckSupported before updating or removing this
    #if os(macOS) || os(Linux) || os(Windows) || os(Android)
    static let isSupportedPlatform = true
    #else
    static let isSupportedPlatform = false
    #endif

    let configuration: Configuration
    private let diagnosticsEngine: DiagnosticsEngine?
    private let storageContainer: (storage: Storage, owned: Bool)
    private let collectionProviders: [Model.CollectionSourceType: PackageCollectionProvider]
    let metadataProvider: PackageMetadataProvider

    private var storage: Storage {
        self.storageContainer.storage
    }

    // initialize with defaults
    public init(configuration: Configuration = .init(), diagnosticsEngine: DiagnosticsEngine = DiagnosticsEngine()) {
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
        try self.metadataProvider.close()
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
                        let sort = { (lhs: PackageCollectionsModel.Collection, rhs: PackageCollectionsModel.Collection) -> Bool in
                            collectionOrder[lhs.identifier] ?? 0 < collectionOrder[rhs.identifier] ?? 0
                        }

                        // We've fetched all the configured collections and we're done
                        if collections.count == sources.count {
                            collections.sort(by: sort)
                            return callback(.success(collections))
                        }

                        // Some of the results are missing. This happens when deserialization of stored collections fail,
                        // so we will try refreshing the missing collections to update data in storage.
                        let missingSources = Set(sources).subtracting(Set(collections.map { $0.source }))
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
                if let errors = source.validate()?.errors() {
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

    // MARK: - Package Metadata

    public func getPackageMetadata(_ reference: PackageReference,
                                   callback: @escaping (Result<PackageCollectionsModel.PackageMetadata, Error>) -> Void) {
        self.getPackageMetadata(reference, collections: nil, callback: callback)
    }

    public func getPackageMetadata(_ reference: PackageReference,
                                   collections: Set<PackageCollectionsModel.CollectionIdentifier>?,
                                   callback: @escaping (Result<PackageCollectionsModel.PackageMetadata, Error>) -> Void) {
        guard Self.isSupportedPlatform else {
            return callback(.failure(PackageCollectionError.unsupportedPlatform))
        }

        // first find in storage
        self.findPackage(identifier: reference.identity, collections: collections) { result in
            switch result {
            case .failure(let error):
                callback(.failure(error))
            case .success(let packageSearchResult):
                // then try to get more metadata from provider (optional)
                let authTokenType = self.metadataProvider.getAuthTokenType(for: reference)
                let isAuthTokenConfigured = authTokenType.flatMap { self.configuration.authTokens()?[$0] } != nil

                self.metadataProvider.get(reference) { result in
                    switch result {
                    case .failure(let error):
                        self.diagnosticsEngine?.emit(warning: "Failed fetching information about \(reference) from \(self.metadataProvider.name): \(error)")

                        let provider: PackageMetadataProviderContext?
                        switch error {
                        case let error as GitHubPackageMetadataProvider.Errors:
                            let providerError = PackageMetadataProviderError.from(error)
                            if providerError == nil {
                                // The metadata provider cannot be used for the package
                                provider = nil
                            } else {
                                provider = PackageMetadataProviderContext(authTokenType: authTokenType, isAuthTokenConfigured: isAuthTokenConfigured, error: providerError)
                            }
                        default:
                            // For all other errors, including NotFoundError, assume the provider is not intended for the package.
                            provider = nil
                        }
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
                            provider: PackageMetadataProviderContext(authTokenType: authTokenType, isAuthTokenConfigured: isAuthTokenConfigured)
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

    func findPackage(identifier: PackageIdentity,
                     collections: Set<PackageCollectionsModel.CollectionIdentifier>?,
                     callback: @escaping (Result<PackageCollectionsModel.PackageSearchResult.Item, Error>) -> Void) {
        self.storage.sources.list { result in
            switch result {
            case .failure(let error):
                callback(.failure(error))
            case .success(let sources):
                var collectionIdentifiers = sources.map { Model.CollectionIdentifier(from: $0) }
                if let collections = collections {
                    collectionIdentifiers = collectionIdentifiers.filter { collections.contains($0) }
                }
                if collectionIdentifiers.isEmpty {
                    return callback(.failure(NotFoundError("\(identifier)")))
                }
                self.storage.collections.findPackage(identifier: identifier, collectionIdentifiers: collectionIdentifiers, callback: callback)
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
                    version.manifests.values.forEach { manifest in
                        manifest.targets.forEach { target in
                            // Avoid copy-on-write: remove entry from dictionary before mutating
                            var entry = targetsPackages.removeValue(forKey: target.name) ?? (target: target, packages: .init())
                            entry.packages.insert(package.reference)
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
        // This dictionary contains recent releases and might not contain everything that's in package.versions.
        let basicVersionMetadata = basicMetadata.map { Dictionary(uniqueKeysWithValues: $0.versions.map { ($0.version, $0) }) } ?? [:]
        var versions = package.versions.map { packageVersion -> Model.Package.Version in
            let versionMetadata = basicVersionMetadata[packageVersion.version]
            return .init(version: packageVersion.version,
                         title: versionMetadata?.title ?? packageVersion.title,
                         summary: versionMetadata?.summary ?? packageVersion.summary,
                         manifests: packageVersion.manifests,
                         defaultToolsVersion: packageVersion.defaultToolsVersion,
                         verifiedCompatibility: packageVersion.verifiedCompatibility,
                         license: packageVersion.license,
                         createdAt: versionMetadata?.createdAt ?? packageVersion.createdAt)
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
