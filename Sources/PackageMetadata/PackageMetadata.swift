//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
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

    public let identity: PackageIdentity
    public let location: String?
    public let branches: [String]
    public let versions: [Version]
    public let readmeURL: URL?
    public let source: Source

    fileprivate init(identity: PackageIdentity, location: String? = nil, branches: [String] = [], versions: [Version], readmeURL: URL? = nil, source: Source) {
        self.identity = identity
        self.location = location
        self.branches = branches
        self.versions = versions
        self.readmeURL = readmeURL
        self.source = source
    }
}

public struct PackageSearchClient {
    private let registryClient: RegistryClient
    private let indexAndCollections: PackageIndexAndCollections
    private let observabilityScope: ObservabilityScope

    public init(
        registryClient: RegistryClient,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope
    ) {
        self.registryClient = registryClient
        self.indexAndCollections = PackageIndexAndCollections(fileSystem: fileSystem, observabilityScope: observabilityScope)
        self.observabilityScope = observabilityScope
    }

    var repositoryProvider: RepositoryProvider {
        return GitRepositoryProvider()
    }

    // FIXME: This matches the current implementation, but we may want be smarter about it?
    private func guessReadMeURL(baseURL: URL, defaultBranch: String) -> URL {
        return baseURL.appendingPathComponent("raw").appendingPathComponent(defaultBranch).appendingPathComponent("README.md")
    }

    public func findPackages(
        _ query: String,
        callback: @escaping (Result<[Package], Error>) -> Void
    ) {
        let identity = PackageIdentity.plain(query)
        let isRegistryIdentity = identity.scopeAndName != nil

        // Search the package index and collections for a search term.
        let search = { (error: Error?) -> Void in
            self.indexAndCollections.findPackages(query) { result in
                do {
                    let packages = try result.get().items.map {
                        Package(identity: $0.package.identity,
                                location: $0.package.location,
                                versions: $0.package.versions.map { $0.version },
                                readmeURL: $0.package.readmeURL,
                                source: .indexAndCollections(collections: $0.collections, indexes: $0.indexes)
                        )
                    }
                    if packages.isEmpty, let error = error {
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

        // Interpret the given search term as a URL and fetch the corresponding Git repository to determine the available version tags and branches. If the search term cannot be interpreted as a URL or there are any errors during the process, we fall back to searching the configured index or package collections.
        let fetchStandalonePackageByURL = { (error: Error?) -> Void in
            guard let url = URL(string: query) else {
                return search(error)
            }

            do {
                try withTemporaryDirectory(removeTreeOnDeinit: true) { (tempDir: AbsolutePath) -> Void in
                    let tempPath = tempDir.appending(component: url.lastPathComponent)
                    do {
                        let repositorySpecifier = RepositorySpecifier(url: url)
                        try self.repositoryProvider.fetch(repository: repositorySpecifier, to: tempPath, progressHandler: nil)
                        if self.repositoryProvider.isValidDirectory(tempPath), let repository = try self.repositoryProvider.open(repository: repositorySpecifier, at: tempPath) as? GitRepository {
                            let branches = try repository.getBranches()
                            let versions = try repository.getTags().compactMap { Version($0) }
                            let package = Package(identity: .init(url: url),
                                                  location: url.absoluteString,
                                                  branches: branches,
                                                  versions: versions,
                                                  readmeURL: self.guessReadMeURL(baseURL: url, defaultBranch: try repository.getDefaultBranch()),
                                                  source: .sourceControl(url: url))
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

        // If the given search term can be interpreted as a registry identity, try to get package metadata for it from the configured registry. If there are any errors or the search term does not work as a registry identity, we will fall back on `fetchStandalonePackageByURL`.
        if isRegistryIdentity {
            return self.registryClient.getPackageMetadata(package: identity, observabilityScope: observabilityScope, callbackQueue: DispatchQueue.sharedConcurrent) { result in
                do {
                    let metadata = try result.get()
                    let readmeURL: URL?
                    if let alternateURL = metadata.alternateLocations?.first {
                        // FIXME: This is pretty crude, we should let the registry metadata provide the value instead.
                        readmeURL = guessReadMeURL(baseURL: alternateURL, defaultBranch: "main")
                    } else {
                        readmeURL = nil
                    }
                    return callback(.success([Package(identity: identity,
                                                      versions: metadata.versions,
                                                      readmeURL: readmeURL,
                                                      source: .registry(url: metadata.registry.url)
                                                     )]))
                } catch {
                    return fetchStandalonePackageByURL(error)
                }
            }
        } else {
            return fetchStandalonePackageByURL(nil)
        }
    }
}
