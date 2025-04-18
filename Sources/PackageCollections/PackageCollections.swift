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

import _Concurrency
import Basics
import PackageModel
import Foundation

import protocol TSCBasic.Closable

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

    public func listCollections(identifiers: Set<PackageCollectionsModel.CollectionIdentifier>? = nil) async throws -> [PackageCollectionsModel.Collection] {
        guard Self.isSupportedPlatform else {
            throw PackageCollectionError.unsupportedPlatform
        }

        let sources = try await self.storage.sources.list()
        let identiferSource = sources.reduce(into: [PackageCollectionsModel.CollectionIdentifier: PackageCollectionsModel.CollectionSource]()) { result, source in
            result[.init(from: source)] = source
        }
        let identifiersToFetch = identiferSource.keys.filter { identifiers?.contains($0) ?? true }

        if identifiersToFetch.isEmpty {
            return []
        }

        var collections = try await self.storage.collections.list(identifiers: identifiersToFetch)

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
            return collections
        }

        // Some of the results are missing. This happens when deserialization of stored collections fail,
        // so we will try refreshing the missing collections to update data in storage.
        let missingSources = Set(identifiersToFetch.compactMap { identiferSource[$0] }).subtracting(Set(collections.map { $0.source }))
        var refreshResults = [Model.Collection]()
        for source in missingSources {
            guard let refreshResult = try? await self.refreshCollectionFromSource(source: source, trustConfirmationProvider: nil) else {
                continue
            }
            refreshResults.append(refreshResult)
        }
        var result = collections + refreshResults
        result.sort(by: sort)
        return result
    }

    public func refreshCollections() async throws -> [PackageCollectionsModel.CollectionSource] {
        guard Self.isSupportedPlatform else {
            throw PackageCollectionError.unsupportedPlatform
        }

        let sources = try await self.storage.sources.list()
        guard !sources.isEmpty else {
            return []
        }

        var refreshResults = [Result<Model.Collection, Error>]()
        for source in sources {
            do {
                try await refreshResults.append(.success(self.refreshCollectionFromSource(source: source, trustConfirmationProvider: nil)))
            } catch {
                refreshResults.append(.failure(error))
            }
        }
        let failures = refreshResults.compactMap { $0.failure }
        guard failures.isEmpty else {
            throw MultipleErrors(failures)
        }
        return sources
    }

    public func refreshCollection(_ source: PackageCollectionsModel.CollectionSource) async throws -> PackageCollectionsModel.Collection {
        guard Self.isSupportedPlatform else {
            throw PackageCollectionError.unsupportedPlatform
        }

        let sources = try await self.storage.sources.list()
        guard let savedSource = sources.first(where: { $0 == source }) else {
            throw NotFoundError("\(source)")
        }
        return try await self.refreshCollectionFromSource(source: savedSource, trustConfirmationProvider: nil)
    }

    public func addCollection(_ source: PackageCollectionsModel.CollectionSource, order: Int? = nil, trustConfirmationProvider: ((PackageCollectionsModel.Collection, @escaping (Bool) -> Void) -> Void)? = nil) async throws -> PackageCollectionsModel.Collection {
        guard Self.isSupportedPlatform else {
            throw PackageCollectionError.unsupportedPlatform
        }

        if let errors = source.validate(fileSystem: self.fileSystem)?.errors() {
            throw MultipleErrors(errors)
        }

        // first record the registration
        try await self.storage.sources.add(source: source, order: order)
        // next try to fetch the collection from the network and store it locally so future operations dont need to access the network
        do {
            return try await self.refreshCollectionFromSource(source: source, trustConfirmationProvider: trustConfirmationProvider)
        } catch {
            // Don't delete the source if we are either pending user confirmation or have recorded user's preference.
            // It is also possible that we can't verify signature (yet) due to config issue, which user can fix and we retry later.
            if let error = error as? PackageCollectionError, error == .trustConfirmationRequired || error == .untrusted || error == .cannotVerifySignature {
                throw error
            }
            // Otherwise remove source since it fails to be fetched
            try? await self.storage.sources.remove(source: source)
            // Whether removal succeeds or not, return the refresh error
            throw error
        }

    }

    public func removeCollection(_ source: PackageCollectionsModel.CollectionSource) async throws {
        guard Self.isSupportedPlatform else {
            throw PackageCollectionError.unsupportedPlatform
        }

        try await self.storage.sources.remove(source: source)
        try await self.storage.collections.remove(identifier: .init(from: source))
    }

    public func moveCollection(_ source: PackageCollectionsModel.CollectionSource, to order: Int) async throws {
        guard Self.isSupportedPlatform else {
            throw PackageCollectionError.unsupportedPlatform
        }

        try await self.storage.sources.move(source: source, to: order)
    }

    public func updateCollection(_ source: PackageCollectionsModel.CollectionSource) async throws -> PackageCollectionsModel.Collection {
        guard Self.isSupportedPlatform else {
            throw PackageCollectionError.unsupportedPlatform
        }

        try await self.storage.sources.update(source: source)
        return try await self.refreshCollectionFromSource(source: source, trustConfirmationProvider: nil)
    }

    // Returns information about a package collection.
    // The collection is not required to be in the configured list.
    // If not found locally (storage), the collection will be fetched from the source.
    public func getCollection(_ source: PackageCollectionsModel.CollectionSource) async throws -> PackageCollectionsModel.Collection {
        guard Self.isSupportedPlatform else {
            throw PackageCollectionError.unsupportedPlatform
        }

        do {
            return try await self.storage.collections.get(identifier: .init(from: source))
        } catch {
            // The collection is not in storage. Validate the source before fetching it.
            if let errors = source.validate(fileSystem: self.fileSystem)?.errors() {
                throw MultipleErrors(errors)
            }
            guard let provider = self.collectionProviders[source.type] else {
                throw UnknownProvider(source.type)
            }
            return try await provider.get(source)
        }
    }

    // MARK: - Packages

    public func findPackages(
        _ query: String,
        collections: Set<PackageCollectionsModel.CollectionIdentifier>? = nil
    ) async throws -> PackageCollectionsModel.PackageSearchResult{
        guard Self.isSupportedPlatform else {
            throw PackageCollectionError.unsupportedPlatform
        }
        let sources = try await self.storage.sources.list()

        let identifiers = sources.map { .init(from: $0) }.filter { collections?.contains($0) ?? true }
        if identifiers.isEmpty {
            return Model.PackageSearchResult(items: [])
        }
        return try await self.storage.collections.searchPackages(identifiers: identifiers, query: query)
    }

    public func listPackages(collections: Set<PackageCollectionsModel.CollectionIdentifier>? = nil) async throws -> PackageCollectionsModel.PackageSearchResult {
        let collections = try await self.listCollections(identifiers: collections)

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

        return PackageCollectionsModel.PackageSearchResult(
            items: packageCollections.sorted { $0.value.package.displayName < $1.value.package.displayName }
                .map { entry in
                .init(package: entry.value.package, collections: Array(entry.value.collections))
                }
        )
    }

    // MARK: - Package Metadata

    public func getPackageMetadata(
        identity: PackageModel.PackageIdentity,
        location: String? = nil,
        collections: Set<PackageCollectionsModel.CollectionIdentifier>? = nil
    ) async throws -> PackageCollectionsModel.PackageMetadata {
        guard Self.isSupportedPlatform else {
            throw PackageCollectionError.unsupportedPlatform
        }

        // first find in storage
        let packageSearchResult = try await self.findPackage(identity: identity, location: location, collections: collections)
        // then try to get more metadata from provider (optional)
        let (basicMetadata, provider) = await self.metadataProvider.get(identity: packageSearchResult.package.identity, location: packageSearchResult.package.location)
        do {
            return try Model.PackageMetadata(
                package: Self.mergedPackageMetadata(package: packageSearchResult.package, basicMetadata: basicMetadata.get()),
                collections: packageSearchResult.collections,
                provider: provider
            )
        } catch {
            self.observabilityScope.emit(
                warning: "Failed fetching information about \(identity) from \(self.metadataProvider.self)",
                underlyingError: error
            )
            return Model.PackageMetadata(
                package: Self.mergedPackageMetadata(package: packageSearchResult.package, basicMetadata: nil),
                collections: packageSearchResult.collections,
                provider: provider
            )
        }
    }

    // MARK: - Targets

    public func listTargets(collections: Set<PackageCollectionsModel.CollectionIdentifier>? = nil) async throws -> PackageCollectionsModel.TargetListResult {
        guard Self.isSupportedPlatform else {
            throw PackageCollectionError.unsupportedPlatform
        }

        let collections = try await self.listCollections(identifiers: collections)
        return self.targetListResultFromCollections(collections)
    }

    public func findTargets(
        _ query: String,
        searchType: PackageCollectionsModel.TargetSearchType? = nil,
        collections: Set<PackageCollectionsModel.CollectionIdentifier>? = nil
    ) async throws -> PackageCollectionsModel.TargetSearchResult {
        guard Self.isSupportedPlatform else {
            throw PackageCollectionError.unsupportedPlatform
        }

        let searchType = searchType ?? .exactMatch

        let sources = try await self.storage.sources.list()
        let identifiers = sources.map { .init(from: $0) }.filter { collections?.contains($0) ?? true }
        if identifiers.isEmpty {
            return PackageCollectionsModel.TargetSearchResult(items: [])
        }
        return try await self.storage.collections.searchTargets(identifiers: identifiers, query: query, type: searchType)
    }

    // MARK: - Private

    // Fetch the collection from the network and store it in local storage
    // This helps avoid network access in normal operations
    private func refreshCollectionFromSource(
        source: PackageCollectionsModel.CollectionSource,
        trustConfirmationProvider: ((PackageCollectionsModel.Collection, @escaping (Bool) -> Void) -> Void)? = nil
    ) async throws -> Model.Collection {
        guard let provider = self.collectionProviders[source.type] else {
            throw UnknownProvider(source.type)
        }
        var collection: Model.Collection
        do {
            collection = try await provider.get(source)
        } catch {
            // Remove the unavailable/invalid collection (if previously saved) from storage before calling back
            try? await self.storage.collections.remove(identifier: PackageCollectionsModel.CollectionIdentifier(from: source))
            throw error
        }
        // If collection is signed and signature is valid, save to storage. `provider.get`
        // would have failed if signature were invalid.
        if collection.isSigned {
            return try await self.storage.collections.put(collection: collection)
        }

        // If collection is not signed, check if it's trusted by user and prompt user if needed.
        if let isTrusted = source.isTrusted {
            guard isTrusted else {
                // Try to remove the untrusted collection (if previously saved) from storage before calling back
                try? await self.storage.collections.remove(identifier: collection.identifier)
                throw PackageCollectionError.untrusted
            }
            return try await self.storage.collections.put(collection: collection)
        }


        // No user preference recorded, so we need to prompt if we can.
        guard let trustConfirmationProvider else {
            // Try to remove the untrusted collection (if previously saved) from storage before calling back
            try? await self.storage.collections.remove(identifier: collection.identifier)
            throw PackageCollectionError.trustConfirmationRequired
        }
        let userTrusted = await withCheckedContinuation { continuation in
            trustConfirmationProvider(collection) { result in
                continuation.resume(returning: result)
            }
        }
        var source = source
        source.isTrusted = userTrusted
        // Record user preference then save collection to storage
        try await self.storage.sources.update(source: source)

        guard userTrusted else {
            // Try to remove the untrusted collection (if previously saved) from storage before calling back
            try? await self.storage.collections.remove(identifier: collection.identifier)
            throw PackageCollectionError.untrusted
        }
        collection.source = source
        return try await self.storage.collections.put(collection: collection)
    }

    func findPackage(identity: PackageIdentity,
                     location: String? = nil,
                     collections: Set<PackageCollectionsModel.CollectionIdentifier>? = nil
    ) async throws -> PackageCollectionsModel.PackageSearchResult.Item {
        let notFoundError = NotFoundError("identity: \(identity), location: \(location ?? "none")")

        let sources: [PackageCollectionsModel.CollectionSource]
        do {
            sources = try await self.storage.sources.list()
        } catch is NotFoundError {
            throw notFoundError
        }

        var collectionIdentifiers = sources.map { Model.CollectionIdentifier(from: $0) }
        if let collections {
            collectionIdentifiers = collectionIdentifiers.filter { collections.contains($0) }
        }
        guard !collectionIdentifiers.isEmpty else {
            throw notFoundError
        }
        let packagesCollections: (packages: [PackageCollectionsModel.Package], collections: [PackageCollectionsModel.CollectionIdentifier])
        do {
            packagesCollections = try await self.storage.collections.findPackage(identifier: identity, collectionIdentifiers: collectionIdentifiers)
        } catch is NotFoundError {
            throw notFoundError
        }

        let matches: [PackageCollectionsModel.Package]
        if let location {
            // A package identity can be associated with multiple repository URLs
            matches = packagesCollections.packages.filter { CanonicalPackageLocation($0.location) == CanonicalPackageLocation(location) }
        }
        else {
            matches = packagesCollections.packages
        }
        guard let package = matches.first else {
            throw notFoundError
        }
        return PackageCollectionsModel.PackageSearchResult.Item(
            package: package,
            collections: packagesCollections.collections)

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
                         author: versionMetadata?.author ?? packageVersion.author,
                         signer: packageVersion.signer,
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
