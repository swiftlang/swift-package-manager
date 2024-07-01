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
import Foundation
import PackageModel

import protocol TSCBasic.Closable

struct PackageIndex: PackageIndexProtocol, Closable {
    private let configuration: PackageIndexConfiguration
    private let httpClient: LegacyHTTPClient
    private let callbackQueue: DispatchQueue
    private let observabilityScope: ObservabilityScope
    
    private let decoder: JSONDecoder

    private let cache: SQLiteBackedCache<CacheValue>?
    
    var isEnabled: Bool {
        self.configuration.enabled && self.configuration.url != .none
    }

    init(
        configuration: PackageIndexConfiguration,
        customHTTPClient: LegacyHTTPClient? = nil,
        callbackQueue: DispatchQueue,
        observabilityScope: ObservabilityScope
    ) {
        self.configuration = configuration
        self.httpClient = customHTTPClient ?? Self.makeDefaultHTTPClient()
        self.callbackQueue = callbackQueue
        self.observabilityScope = observabilityScope
        
        self.decoder = JSONDecoder.makeWithDefaults()
        
        if configuration.cacheTTLInSeconds > 0 {
            var cacheConfig = SQLiteBackedCacheConfiguration()
            cacheConfig.maxSizeInMegabytes = configuration.cacheMaxSizeInMegabytes
            self.cache = SQLiteBackedCache<CacheValue>(
                tableName: "package_index_cache",
                path: configuration.cacheDirectory.appending("index-package-metadata.db"),
                configuration: cacheConfig
            )
        } else {
            self.cache = nil
        }
    }
    
    func close() throws {
        try self.cache?.close()
    }

    func getPackageMetadata(
        identity: PackageIdentity,
        location: String?
    ) async throws -> PackageCollectionsModel.PackageMetadata {
        let url = try await self.urlIfConfigured()
        if let cached = try? self.cache?.get(key: identity.description),
           cached.dispatchTime + DispatchTimeInterval.seconds(self.configuration.cacheTTLInSeconds) > DispatchTime.now() {
            return (package: cached.package, collections: [], provider: self.createContext(host: url.host, error: nil))
        }

        // TODO: rdar://87582621 call package index's get metadata API
        let metadataURL = url.appendingPathComponent("packages").appendingPathComponent(identity.description)
        let response = try await self.httpClient.get(metadataURL)
        switch response.statusCode {
        case 200:
            guard let package = try response.decodeBody(PackageCollectionsModel.Package.self, using: self.decoder) else {
                throw PackageIndexError.invalidResponse(metadataURL, "Empty body")
            }

            do {
                try self.cache?.put(
                    key: identity.description,
                    value: CacheValue(package: package, timestamp: DispatchTime.now()),
                    replace: true,
                    observabilityScope: self.observabilityScope
                )
            } catch {
                self.observabilityScope.emit(
                    warning: "Failed to save index metadata for package \(identity) to cache",
                    underlyingError: error
                )
            }

            return (package: package, collections: [], provider: self.createContext(host: url.host, error: nil))
        default:
            throw PackageIndexError.invalidResponse(metadataURL, "Invalid status code: \(response.statusCode)")
        }
    }
    
    func findPackages(
        _ query: String
    ) async throws -> PackageCollectionsModel.PackageSearchResult {
        let url = try await self.urlIfConfigured()
        guard var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            throw PackageIndexError.invalidURL(url)
        }
        urlComponents.path = (urlComponents.path.last == "/" ? "" : "/") + "search"
        urlComponents.queryItems = [
            URLQueryItem(name: "q", value: query),
        ]

        // TODO: rdar://87582621 call package index's search API
        guard let searchURL = urlComponents.url else {
            throw PackageIndexError.invalidURL(url)
        }
        let response = try await self.httpClient.get(searchURL)
        switch response.statusCode {
        case 200:
            guard let packages = try response.decodeBody([PackageCollectionsModel.Package].self, using: self.decoder) else {
                throw PackageIndexError.invalidResponse(searchURL, "Empty body")
            }
            // Limit the number of items
            let items = packages[..<min(packages.count, self.configuration.searchResultMaxItemsCount)].map {
                PackageCollectionsModel.PackageSearchResult.Item(package: $0, indexes: [url])
            }
            return PackageCollectionsModel.PackageSearchResult(items: items)
        default:
            throw PackageIndexError.invalidResponse(searchURL, "Invalid status code: \(response.statusCode)")
        }
    }

    func listPackages(
        offset: Int,
        limit: Int
    ) async throws -> PackageCollectionsModel.PaginatedPackageList {
        let url = try await self.urlIfConfigured()

        guard var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            throw PackageIndexError.invalidURL(url)
        }
        urlComponents.path = (urlComponents.path.last == "/" ? "" : "/") + "packages"
        urlComponents.queryItems = [
            URLQueryItem(name: "offset", value: "\(offset)"),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ]

        // TODO: rdar://87582621 call package index's list API
        guard let listURL = urlComponents.url else {
            throw PackageIndexError.invalidURL(url)
        }
        let response = try await self.httpClient.get(listURL)
        switch response.statusCode {
        case 200:
            guard let listResponse = try response.decodeBody(ListResponse.self, using: self.decoder) else {
                throw PackageIndexError.invalidResponse(listURL, "Empty body")
            }
            return PackageCollectionsModel.PaginatedPackageList(
                items: listResponse.items,
                offset: offset,
                limit: limit,
                total: listResponse.total
            )
        default:
            throw PackageIndexError.invalidResponse(listURL, "Invalid status code: \(response.statusCode)")
        }
    }

    private func urlIfConfigured() async throws -> URL {
        guard self.configuration.enabled else {
            throw PackageIndexError.featureDisabled
        }
        guard let url = self.configuration.url else {
            throw PackageIndexError.notConfigured
        }
        return url
    }
    
    private func createContext(host: String?, error: Error?) -> PackageMetadataProviderContext? {
        let name = host ?? "package index"
        return PackageMetadataProviderContext(
            name: name,
            // Package index doesn't require auth
            authTokenType: nil,
            isAuthTokenConfigured: true
        )
    }
    
    private static func makeDefaultHTTPClient() -> LegacyHTTPClient {
        let client = LegacyHTTPClient()
        // TODO: make these defaults configurable?
        client.configuration.requestTimeout = .seconds(1)
        client.configuration.retryStrategy = .exponentialBackoff(maxAttempts: 3, baseDelay: .milliseconds(50))
        client.configuration.circuitBreakerStrategy = .hostErrors(maxErrors: 50, age: .seconds(30))
        return client
    }

    private struct CacheValue: Codable {
        let package: Model.Package
        let timestamp: UInt64

        var dispatchTime: DispatchTime {
            DispatchTime(uptimeNanoseconds: self.timestamp)
        }

        init(package: Model.Package, timestamp: DispatchTime) {
            self.package = package
            self.timestamp = timestamp.uptimeNanoseconds
        }
    }
}

extension PackageIndex {
    struct ListResponse: Codable {
        let items: [PackageCollectionsModel.Package]
        let total: Int
    }
}

// MARK: - PackageMetadataProvider conformance

extension PackageIndex: PackageMetadataProvider {
    func get(
        identity: PackageIdentity,
        location: String
    ) async -> (Result<PackageCollectionsModel.PackageBasicMetadata, Error>, PackageMetadataProviderContext?) {
        do {
            let metadata = try await self.getPackageMetadata(identity: identity, location: location)

            let package = metadata.package
            let basicMetadata = PackageCollectionsModel.PackageBasicMetadata(
                summary: package.summary,
                keywords: package.keywords,
                versions: package.versions.map { version in
                    PackageCollectionsModel.PackageBasicVersionMetadata(
                        version: version.version,
                        title: version.title,
                        summary: version.summary,
                        author: version.author,
                        createdAt: version.createdAt
                    )
                },
                watchersCount: package.watchersCount,
                readmeURL: package.readmeURL,
                license: package.license,
                authors: package.authors,
                languages: package.languages
            )
            return (.success(basicMetadata), metadata.provider)
        } catch {
            return (.failure(error), nil)
        }
    }
}
