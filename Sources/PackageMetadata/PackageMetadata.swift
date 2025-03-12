//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Dispatch
import PackageCollections
import PackageModel
import PackageRegistry
import PackageSigning
import SourceControl

import struct Foundation.Date
import struct Foundation.URL

import struct TSCUtility.Version

public struct Package {
    public enum Source {
        case indexAndCollections(collections: [PackageCollectionsModel.CollectionIdentifier], indexes: [URL])
        case registry(url: URL)
        case sourceControl(url: SourceControlURL)
    }

    public struct Resource: Sendable {
        public let name: String
        public let type: String
        public let checksum: String?
        public let signing: Signing?
        public let signingEntity: RegistryReleaseMetadata.SigningEntity?
    }

    public struct Signing: Sendable {
        public let signatureBase64Encoded: String
        public let signatureFormat: String
    }

    public struct Author: Sendable {
        public let name: String
        public let email: String?
        public let description: String?
        public let organization: Organization?
        public let url: URL?
    }

    public struct Organization: Sendable {
        public let name: String
        public let email: String?
        public let description: String?
        public let url: URL?
    }

    public let identity: PackageIdentity
    public let location: String?
    public let branches: [String]
    public let versions: [Version]
    public let source: Source

    // Per version metadata based on the latest version that we include here for convenience.
    public let licenseURL: URL?
    public let readmeURL: URL?
    public let repositoryURLs: [SourceControlURL]?
    public let resources: [Resource]
    public let author: Author?
    public let description: String?
    public let publishedAt: Date?
    public let signingEntity: SigningEntity?
    public let latestVersion: Version?

    fileprivate init(
        identity: PackageIdentity,
        location: String? = nil,
        branches: [String] = [],
        versions: [Version],
        licenseURL: URL? = nil,
        readmeURL: URL? = nil,
        repositoryURLs: [SourceControlURL]? = nil,
        resources: [Resource] = [],
        author: Author? = nil,
        description: String? = nil,
        publishedAt: Date? = nil,
        signingEntity: SigningEntity? = nil,
        latestVersion: Version? = nil,
        source: Source
    ) {
        self.identity = identity
        self.location = location
        self.branches = branches
        self.versions = versions
        self.licenseURL = licenseURL
        self.readmeURL = readmeURL
        self.repositoryURLs = repositoryURLs
        self.resources = resources
        self.author = author
        self.description = description
        self.publishedAt = publishedAt
        self.signingEntity = signingEntity
        self.latestVersion = latestVersion
        self.source = source
    }
}

public struct PackageSearchClient {
    private let fileSystem: FileSystem
    private let registryClient: RegistryClient
    private let indexAndCollections: PackageIndexAndCollections
    private let observabilityScope: ObservabilityScope

    public init(
        registryClient: RegistryClient,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope
    ) {
        self.registryClient = registryClient
        self.indexAndCollections = PackageIndexAndCollections(
            fileSystem: fileSystem,
            observabilityScope: observabilityScope
        )
        self.fileSystem = fileSystem
        self.observabilityScope = observabilityScope
    }

    var repositoryProvider: RepositoryProvider {
        GitRepositoryProvider()
    }

    // FIXME: This matches the current implementation, but we may want be smarter about it?
    private func guessReadMeURL(baseURL: SourceControlURL, defaultBranch: String) -> URL? {
        if let baseURL = baseURL.url {
            return guessReadMeURL(baseURL: baseURL, defaultBranch: defaultBranch)
        } else {
            return nil
        }
    }

    private func guessReadMeURL(baseURL: URL, defaultBranch: String) -> URL {
        baseURL.appendingPathComponent("raw").appendingPathComponent(defaultBranch).appendingPathComponent("README.md")
    }



    private func guessReadMeURL(alternateLocations: [SourceControlURL]?) -> URL? {
        if let alternateURL = alternateLocations?.first {
            // FIXME: This is pretty crude, we should let the registry metadata provide the value instead.
            return guessReadMeURL(baseURL: alternateURL, defaultBranch: "main")
        }
        return nil
    }

    private struct Metadata {
        public let licenseURL: URL?
        public let readmeURL: URL?
        public let repositoryURLs: [SourceControlURL]?
        public let resources: [Package.Resource]
        public let author: Package.Author?
        public let description: String?
        public let publishedAt: Date?
        public let signingEntity: SigningEntity?
    }

    private func getVersionMetadata(
        package: PackageIdentity,
        version: Version
    ) async throws -> Metadata {
        let metadata = try await self.registryClient.getPackageVersionMetadata(
            package: package,
            version: version,
            fileSystem: self.fileSystem,
            observabilityScope: observabilityScope
        )

        return Metadata(
            licenseURL: metadata.licenseURL,
            readmeURL: metadata.readmeURL,
            repositoryURLs: metadata.repositoryURLs,
            resources: metadata.resources.map { .init($0) },
            author: metadata.author.map { .init($0) },
            description: metadata.description,
            publishedAt: metadata.publishedAt,
            signingEntity: metadata.sourceArchive?.signingEntity
        )
    }

    public func findPackages(
        _ query: String
    ) async throws -> [Package] {
        let identity = PackageIdentity.plain(query)

        // Search the package index and collections for a search term.
        let search = { (error: Error?) async throws -> [Package] in
            let result = try await self.indexAndCollections.findPackages(query)
            let packages = result.items.map {
                let versions = $0.package.versions.sorted(by: >)
                let latestVersion = versions.first

                return Package(
                    identity: $0.package.identity,
                    location: $0.package.location,
                    versions: $0.package.versions.map(\.version),
                    licenseURL: $0.package.license?.url,
                    readmeURL: $0.package.readmeURL,
                    repositoryURLs: nil,
                    resources: [],
                    author: latestVersion?.author.map { .init($0) },
                    description: latestVersion?.summary,
                    publishedAt: latestVersion?.createdAt,
                    signingEntity: latestVersion?.signer.map { SigningEntity(signer: $0) },
                    latestVersion: latestVersion?.version,
                    // this only makes sense in connection with providing versioned metadata
                    source: .indexAndCollections(collections: $0.collections, indexes: $0.indexes)
                )
            }
            if packages.isEmpty, let error {
                // If the search result is empty and we had a previous error, emit it now.
                throw error
            }
            return packages
        }

        // Interpret the given search term as a URL and fetch the corresponding Git repository to
        // determine the available version tags and branches. If the search term cannot be interpreted
        // as a URL or there are any errors during the process, we fall back to searching the configured
        // index or package collections.
        let fetchStandalonePackageByURL = { (error: Error?) async throws -> [Package] in
            let url = SourceControlURL(query)
            do {
                return try withTemporaryDirectory(removeTreeOnDeinit: true) { (tempDir: AbsolutePath) in
                    let tempPath = tempDir.appending(component: url.lastPathComponent)
                    let repositorySpecifier = RepositorySpecifier(url: url)
                    try self.repositoryProvider.fetch(
                        repository: repositorySpecifier,
                        to: tempPath,
                        progressHandler: nil
                    )
                    guard try self.repositoryProvider.isValidDirectory(tempPath), let repository = try self.repositoryProvider.open(
                        repository: repositorySpecifier,
                        at: tempPath
                    ) as? GitRepository else {
                        return []
                    }

                    let branches = try repository.getBranches()
                    let versions = try repository.getTags().compactMap { Version($0) }
                    let package = Package(
                        identity: .init(url: url),
                        location: url.absoluteString,
                        branches: branches,
                        versions: versions,
                        licenseURL: nil,
                        readmeURL: self.guessReadMeURL(
                            baseURL: url,
                            defaultBranch: try repository.getDefaultBranch()
                        ),
                        repositoryURLs: nil,
                        resources: [],
                        author: nil,
                        description: nil,
                        publishedAt: nil,
                        signingEntity: nil,
                        latestVersion: nil,
                        // this only makes sense in connection with providing versioned metadata
                        source: .sourceControl(url: url)
                    )
                    return [package]
                }
            } catch {
                return try await search(error)
            }
        }

        // If the given search term can be interpreted as a registry identity, try to get
        // package metadata for it from the configured registry. If there are any errors
        // or the search term does not work as a registry identity, we will fall back on
        // `fetchStandalonePackageByURL`.
        guard identity.isRegistry else {
            return try await fetchStandalonePackageByURL(nil)
        }
        let metadata: RegistryClient.PackageMetadata
        do {
            metadata = try await self.registryClient.getPackageMetadata(
                package: identity,
                observabilityScope: observabilityScope
            )
        } catch {
            return try await fetchStandalonePackageByURL(error)
        }

        let versions = metadata.versions.sorted(by: >)

        // See if the latest package version has readmeURL set
        guard let version = versions.first else {
            let readmeURL: URL? = self.guessReadMeURL(alternateLocations: metadata.alternateLocations)
            return [Package(
                identity: identity,
                versions: versions,
                readmeURL: readmeURL,
                // this only makes sense in connection with providing versioned metadata
                source: .registry(url: metadata.registry.url)
            )]
        }

        let versionMetadata = try? await self.getVersionMetadata(package: identity, version: version)
        return [Package(
            identity: identity,
            versions: versions,
            licenseURL: versionMetadata?.licenseURL,
            readmeURL: versionMetadata?.readmeURL,
            repositoryURLs: versionMetadata?.repositoryURLs,
            resources: versionMetadata?.resources ?? [],
            author: versionMetadata?.author,
            description: versionMetadata?.description,
            publishedAt: versionMetadata?.publishedAt,
            signingEntity: versionMetadata?.signingEntity,
            latestVersion: version,
            source: .registry(url: metadata.registry.url)
        )]
    }

    public func lookupIdentities(
        scmURL: SourceControlURL,
        timeout: DispatchTimeInterval? = .none,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<Set<PackageIdentity>, Error>) -> Void
    ) {
        registryClient.lookupIdentities(
            scmURL: scmURL,
            timeout: timeout,
            observabilityScope: observabilityScope,
            callbackQueue: callbackQueue,
            completion: completion
        )
    }

    public func lookupSCMURLs(
        package: PackageIdentity,
        timeout: DispatchTimeInterval? = .none,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<Set<SourceControlURL>, Error>) -> Void
    ) {
        registryClient.getPackageMetadata(
            package: package,
            timeout: timeout,
            observabilityScope: observabilityScope,
            callbackQueue: callbackQueue
        ) { result in
            do {
                let metadata = try result.get()
                let alternateLocations = metadata.alternateLocations
                return completion(.success(Set(alternateLocations)))
            } catch {
                return completion(.failure(error))
            }
        }
    }
}

extension Package.Signing {
    fileprivate init(_ signing: RegistryClient.PackageVersionMetadata.Signing) {
        self.init(
            signatureBase64Encoded: signing.signatureBase64Encoded,
            signatureFormat: signing.signatureFormat
        )
    }
}

extension RegistryReleaseMetadata.SigningEntity {
    fileprivate init(_ entity: SigningEntity) {
        switch entity {
        case .recognized(let type, let name, let organizationalUnit, let organization):
            self = .recognized(type: type.rawValue, commonName: name, organization: organization, identity: organizationalUnit)
        case .unrecognized(let name, _, let organization):
            self = .unrecognized(commonName: name, organization: organization)
        }
    }
}

extension Package.Resource {
    fileprivate init(_ resource: RegistryClient.PackageVersionMetadata.Resource) {
        self.init(
            name: resource.name,
            type: resource.type,
            checksum: resource.checksum,
            signing: resource.signing.map { .init($0) },
            signingEntity: resource.signingEntity.map { .init($0) }
        )
    }
}

extension Package.Author {
    fileprivate init(_ author: RegistryClient.PackageVersionMetadata.Author) {
        self.init(
            name: author.name,
            email: author.email,
            description: author.description,
            organization: author.organization.map { .init($0) },
            url: author.url
        )
    }

    fileprivate init(_ author: PackageCollectionsModel.Package.Author) {
        self.init(
            name: author.username,
            email: nil,
            description: nil,
            organization: nil,
            url: author.url
        )
    }
}

extension Package.Organization {
    fileprivate init(_ organization: RegistryClient.PackageVersionMetadata.Organization) {
        self.init(
            name: organization.name,
            email: organization.email,
            description: organization.description,
            url: organization.url
        )
    }
}

extension SigningEntity {
    fileprivate init(signer: PackageCollectionsModel.Signer) {
        // All package collection signers are "recognized"
        self = .recognized(
            type: .init(signer.type),
            name: signer.commonName,
            organizationalUnit: signer.organizationalUnitName,
            organization: signer.organizationName
        )
    }
}

extension SigningEntityType {
    fileprivate init(_ type: PackageCollectionsModel.SignerType) {
        switch type {
        case .adp:
            self = .adp
        }
    }
}
