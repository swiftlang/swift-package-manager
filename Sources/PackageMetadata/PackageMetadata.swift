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
import SourceControl

import struct Foundation.Date
import struct Foundation.URL
import struct TSCBasic.AbsolutePath
import protocol TSCBasic.FileSystem
import func TSCBasic.withTemporaryDirectory
import struct TSCUtility.Version

public struct Package {
    public enum Source {
        case indexAndCollections(collections: [PackageCollectionsModel.CollectionIdentifier], indexes: [URL])
        case registry(url: URL)
        case sourceControl(url: URL)
    }

    public struct Resource: Sendable {
        public let name: String
        public let type: String
        public let checksum: String?
        public let signing: Signing?
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
    public let repositoryURLs: [URL]?
    public let resources: [Resource]
    public let author: Author?
    public let description: String?
    public let publishedAt: Date?
    public let latestVersion: Version?

    fileprivate init(
        identity: PackageIdentity,
        location: String? = nil,
        branches: [String] = [],
        versions: [Version],
        licenseURL: URL? = nil,
        readmeURL: URL? = nil,
        repositoryURLs: [URL]?,
        resources: [Resource],
        author: Author?,
        description: String?,
        publishedAt: Date?,
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
    private func guessReadMeURL(baseURL: URL, defaultBranch: String) -> URL {
        baseURL.appendingPathComponent("raw").appendingPathComponent(defaultBranch).appendingPathComponent("README.md")
    }

    private func guessReadMeURL(alternateLocations: [URL]?) -> URL? {
        if let alternateURL = alternateLocations?.first {
            // FIXME: This is pretty crude, we should let the registry metadata provide the value instead.
            return guessReadMeURL(baseURL: alternateURL, defaultBranch: "main")
        }
        return nil
    }

    private struct Metadata {
        public let licenseURL: URL?
        public let readmeURL: URL?
        public let repositoryURLs: [URL]?
        public let resources: [Package.Resource]
        public let author: Package.Author?
        public let description: String?
        public let publishedAt: Date?
    }

    private func getVersionMetadata(
        package: PackageIdentity,
        version: Version,
        callback: @escaping (Result<Metadata, Error>) -> Void
    ) {
        self.registryClient.getPackageVersionMetadata(
            package: package,
            version: version,
            fileSystem: self.fileSystem,
            observabilityScope: observabilityScope,
            callbackQueue: DispatchQueue.sharedConcurrent
        ) { result in
            callback(result.tryMap { metadata in
                Metadata(
                    licenseURL: metadata.licenseURL,
                    readmeURL: metadata.readmeURL,
                    repositoryURLs: metadata.repositoryURLs,
                    resources: metadata.resources.map { .init($0) },
                    author: metadata.author.map { .init($0) },
                    description: metadata.description,
                    publishedAt: metadata.publishedAt
                )
            })
        }
    }

    public func findPackages(
        _ query: String,
        callback: @escaping (Result<[Package], Error>) -> Void
    ) {
        let identity = PackageIdentity.plain(query)

        // Search the package index and collections for a search term.
        let search = { (error: Error?) in
            self.indexAndCollections.findPackages(query) { result in
                do {
                    let packages = try result.get().items.map {
                        Package(
                            identity: $0.package.identity,
                            location: $0.package.location,
                            versions: $0.package.versions.map(\.version),
                            licenseURL: nil,
                            readmeURL: $0.package.readmeURL,
                            repositoryURLs: nil,
                            resources: [],
                            author: nil,
                            description: nil,
                            publishedAt: nil,
                            latestVersion: nil,
                            // this only makes sense in connection with providing versioned metadata
                            source: .indexAndCollections(collections: $0.collections, indexes: $0.indexes)
                        )
                    }
                    if packages.isEmpty, let error {
                        // If the search result is empty and we had a previous error, emit it now.
                        return callback(.failure(error))
                    } else {
                        return callback(.success(packages))
                    }
                } catch {
                    return callback(.failure(error))
                }
            }
        }

        // Interpret the given search term as a URL and fetch the corresponding Git repository to
        // determine the available version tags and branches. If the search term cannot be interpreted
        // as a URL or there are any errors during the process, we fall back to searching the configured
        // index or package collections.
        let fetchStandalonePackageByURL = { (error: Error?) in
            guard let url = URL(string: query) else {
                return search(error)
            }

            do {
                try withTemporaryDirectory(removeTreeOnDeinit: true) { (tempDir: AbsolutePath) in
                    let tempPath = tempDir.appending(component: url.lastPathComponent)
                    do {
                        let repositorySpecifier = RepositorySpecifier(url: url)
                        try self.repositoryProvider.fetch(
                            repository: repositorySpecifier,
                            to: tempPath,
                            progressHandler: nil
                        )
                        if self.repositoryProvider.isValidDirectory(tempPath),
                           let repository = try self.repositoryProvider.open(
                               repository: repositorySpecifier,
                               at: tempPath
                           ) as? GitRepository
                        {
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
                                latestVersion: nil,
                                // this only makes sense in connection with providing versioned metadata
                                source: .sourceControl(url: url)
                            )
                            return callback(.success([package]))
                        }
                    } catch {
                        return search(error)
                    }
                }
            } catch {
                return search(error)
            }
        }

        // If the given search term can be interpreted as a registry identity, try to get
        // package metadata for it from the configured registry. If there are any errors
        // or the search term does not work as a registry identity, we will fall back on
        // `fetchStandalonePackageByURL`.
        if identity.isRegistry {
            return self.registryClient.getPackageMetadata(
                package: identity,
                observabilityScope: observabilityScope,
                callbackQueue: DispatchQueue.sharedConcurrent
            ) { result in
                do {
                    let metadata = try result.get()
                    let versions = metadata.versions.sorted(by: >)

                    // See if the latest package version has readmeURL set
                    if let version = versions.first {
                        self.getVersionMetadata(package: identity, version: version) { result in
                            let licenseURL: URL?
                            let readmeURL: URL?
                            let repositoryURLs: [URL]?
                            let resources: [Package.Resource]
                            let author: Package.Author?
                            let description: String?
                            let publishedAt: Date?
                            if case .success(let metadata) = result {
                                licenseURL = metadata.licenseURL
                                readmeURL = metadata.readmeURL
                                repositoryURLs = metadata.repositoryURLs
                                resources = metadata.resources
                                author = metadata.author
                                description = metadata.description
                                publishedAt = metadata.publishedAt
                            } else {
                                licenseURL = nil
                                readmeURL = self.guessReadMeURL(alternateLocations: metadata.alternateLocations)
                                repositoryURLs = nil
                                resources = []
                                author = nil
                                description = nil
                                publishedAt = nil
                            }

                            return callback(.success([Package(
                                identity: identity,
                                versions: metadata.versions,
                                licenseURL: licenseURL,
                                readmeURL: readmeURL,
                                repositoryURLs: repositoryURLs,
                                resources: resources,
                                author: author,
                                description: description,
                                publishedAt: publishedAt,
                                latestVersion: version,
                                source: .registry(url: metadata.registry.url)
                            )]))
                        }
                    } else {
                        let readmeURL: URL? = self.guessReadMeURL(alternateLocations: metadata.alternateLocations)
                        return callback(.success([Package(
                            identity: identity,
                            versions: metadata.versions,
                            licenseURL: nil,
                            readmeURL: readmeURL,
                            repositoryURLs: nil,
                            resources: [],
                            author: nil,
                            description: nil,
                            publishedAt: nil,
                            latestVersion: nil,
                            // this only makes sense in connection with providing versioned metadata
                            source: .registry(url: metadata.registry.url)
                        )]))
                    }
                } catch {
                    return fetchStandalonePackageByURL(error)
                }
            }
        } else {
            return fetchStandalonePackageByURL(nil)
        }
    }

    public func lookupIdentities(
        scmURL: URL,
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
        completion: @escaping (Result<Set<URL>, Error>) -> Void
    ) {
        registryClient.getPackageMetadata(
            package: package,
            timeout: timeout,
            observabilityScope: observabilityScope,
            callbackQueue: callbackQueue
        ) { result in
            do {
                let metadata = try result.get()
                let alternateLocations = metadata.alternateLocations ?? []
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

extension Package.Resource {
    fileprivate init(_ resource: RegistryClient.PackageVersionMetadata.Resource) {
        self.init(
            name: resource.name,
            type: resource.type,
            checksum: resource.checksum,
            signing: resource.signing.map { .init($0) }
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
