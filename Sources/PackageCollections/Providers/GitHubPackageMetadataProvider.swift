/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020-2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import Dispatch
import struct Foundation.Date
import class Foundation.JSONDecoder
import struct Foundation.NSRange
import class Foundation.NSRegularExpression
import struct Foundation.URL
import PackageModel
import TSCBasic

struct GitHubPackageMetadataProvider: PackageMetadataProvider {
    public var name: String = "GitHub"

    var configuration: Configuration

    private let httpClient: HTTPClient
    private let diagnosticsEngine: DiagnosticsEngine?
    private let decoder: JSONDecoder

    private let cache: SQLiteBackedCache<CacheValue>?

    init(configuration: Configuration = .init(), httpClient: HTTPClient? = nil, diagnosticsEngine: DiagnosticsEngine? = nil) {
        self.configuration = configuration
        self.httpClient = httpClient ?? Self.makeDefaultHTTPClient(diagnosticsEngine: diagnosticsEngine)
        self.diagnosticsEngine = diagnosticsEngine
        self.decoder = JSONDecoder.makeWithDefaults()
        if configuration.cacheTTLInSeconds > 0 {
            var cacheConfig = SQLiteBackedCacheConfiguration()
            cacheConfig.maxSizeInMegabytes = configuration.cacheSizeInMegabytes
            self.cache = SQLiteBackedCache<CacheValue>(tableName: "github_cache", path: configuration.cacheDir.appending(component: "package-metadata.db"), configuration: cacheConfig, diagnosticsEngine: diagnosticsEngine)
        } else {
            self.cache = nil
        }
    }

    func close() throws {
        try self.cache?.close()
    }

    func get(_ reference: PackageReference, callback: @escaping (Result<Model.PackageBasicMetadata, Error>) -> Void) {
        guard reference.kind == .remote else {
            return callback(.failure(Errors.invalidReferenceType(reference)))
        }
        guard let baseURL = Self.apiURL(reference.location) else {
            return callback(.failure(Errors.invalidGitURL(reference.location)))
        }

        if let cached = try? self.cache?.get(key: reference.identity.description) {
            if cached.dispatchTime + DispatchTimeInterval.seconds(self.configuration.cacheTTLInSeconds) > DispatchTime.now() {
                return callback(.success(cached.package))
            }
        }

        let metadataURL = baseURL
        // TODO: make `per_page` configurable? GitHub API's max/default is 100
        let releasesURL = URL(string: baseURL.appendingPathComponent("releases").absoluteString + "?per_page=20") ?? baseURL.appendingPathComponent("releases")
        let contributorsURL = baseURL.appendingPathComponent("contributors")
        let readmeURL = baseURL.appendingPathComponent("readme")
        let licenseURL = baseURL.appendingPathComponent("license")
        let languagesURL = baseURL.appendingPathComponent("languages")

        let sync = DispatchGroup()
        let results = ThreadSafeKeyValueStore<URL, Result<HTTPClientResponse, Error>>()

        // get the main data
        sync.enter()
        var metadataHeaders = HTTPClientHeaders()
        metadataHeaders.add(name: "Accept", value: "application/vnd.github.mercy-preview+json")
        let metadataOptions = self.makeRequestOptions(validResponseCodes: [200, 401, 403, 404])
        let hasAuthorization = metadataOptions.authorizationProvider?(metadataURL) != nil
        httpClient.get(metadataURL, headers: metadataHeaders, options: metadataOptions) { result in
            defer { sync.leave() }
            results[metadataURL] = result
            if case .success(let response) = result {
                let apiLimit = response.headers.get("X-RateLimit-Limit").first.flatMap(Int.init) ?? -1
                let apiRemaining = response.headers.get("X-RateLimit-Remaining").first.flatMap(Int.init) ?? -1
                switch (response.statusCode, hasAuthorization, apiRemaining) {
                case (_, _, 0):
                    self.diagnosticsEngine?.emit(warning: "Exceeded API limits on \(metadataURL.host ?? metadataURL.absoluteString) (\(apiRemaining)/\(apiLimit)), consider configuring an API token for this service.")
                    results[metadataURL] = .failure(Errors.apiLimitsExceeded(metadataURL, apiLimit))
                case (401, true, _):
                    results[metadataURL] = .failure(Errors.invalidAuthToken(metadataURL))
                case (401, false, _):
                    results[metadataURL] = .failure(Errors.permissionDenied(metadataURL))
                case (403, _, _):
                    results[metadataURL] = .failure(Errors.permissionDenied(metadataURL))
                case (404, _, _):
                    results[metadataURL] = .failure(NotFoundError("\(baseURL)"))
                case (200, _, _):
                    if apiRemaining < self.configuration.apiLimitWarningThreshold {
                        self.diagnosticsEngine?.emit(warning: "Approaching API limits on \(metadataURL.host ?? metadataURL.absoluteString) (\(apiRemaining)/\(apiLimit)), consider configuring an API token for this service.")
                    }
                    // if successful, fan out multiple API calls
                    [releasesURL, contributorsURL, readmeURL, licenseURL, languagesURL].forEach { url in
                        sync.enter()
                        var headers = HTTPClientHeaders()
                        headers.add(name: "Accept", value: "application/vnd.github.v3+json")
                        let options = self.makeRequestOptions(validResponseCodes: [200])
                        self.httpClient.get(url, headers: headers, options: options) { result in
                            defer { sync.leave() }
                            results[url] = result
                        }
                    }
                default:
                    results[metadataURL] = .failure(Errors.invalidResponse(metadataURL, "Invalid status code: \(response.statusCode)"))
                }
            }
        }

        // process results
        sync.notify(queue: self.httpClient.configuration.callbackQueue) {
            do {
                // check for main request error state
                switch results[metadataURL] {
                case .none:
                    throw Errors.invalidResponse(metadataURL, "Response missing")
                case .some(.failure(let error)):
                    throw error
                case .some(.success(let metadataResponse)):
                    guard let metadata = try metadataResponse.decodeBody(GetRepositoryResponse.self, using: self.decoder) else {
                        throw Errors.invalidResponse(metadataURL, "Empty body")
                    }
                    let releases = try results[releasesURL]?.success?.decodeBody([Release].self, using: self.decoder) ?? []
                    let contributors = try results[contributorsURL]?.success?.decodeBody([Contributor].self, using: self.decoder)
                    let readme = try results[readmeURL]?.success?.decodeBody(Readme.self, using: self.decoder)
                    let license = try results[licenseURL]?.success?.decodeBody(License.self, using: self.decoder)
                    let languages = try results[languagesURL]?.success?.decodeBody([String: Int].self, using: self.decoder)?.keys

                    let model = Model.PackageBasicMetadata(
                        summary: metadata.description,
                        keywords: metadata.topics,
                        // filters out non-semantic versioned tags
                        versions: releases.compactMap {
                            guard let version = $0.tagName.flatMap(TSCUtility.Version.init(string:)) else {
                                return nil
                            }
                            return Model.PackageBasicVersionMetadata(version: version, title: $0.name, summary: $0.body, createdAt: $0.createdAt, publishedAt: $0.publishedAt)
                        },
                        watchersCount: metadata.watchersCount,
                        readmeURL: readme?.downloadURL,
                        license: license.flatMap { .init(type: Model.LicenseType(string: $0.license.spdxID), url: $0.downloadURL) },
                        authors: contributors?.map { .init(username: $0.login, url: $0.url, service: .init(name: "GitHub")) },
                        languages: languages.flatMap(Set.init) ?? metadata.language.map { [$0] },
                        processedAt: Date()
                    )

                    do {
                        try self.cache?.put(key: reference.identity.description, value: CacheValue(package: model, timestamp: DispatchTime.now()), replace: true)
                    } catch {
                        self.diagnosticsEngine?.emit(.warning("Failed to save GitHub metadata for package \(reference) to cache: \(error)"))
                    }

                    callback(.success(model))
                }
            } catch {
                return callback(.failure(error))
            }
        }
    }

    internal static func apiURL(_ url: String) -> Foundation.URL? {
        do {
            let regex = try NSRegularExpression(pattern: #"([^/@]+)[:/]([^:/]+)/([^/.]+)(\.git)?$"#, options: .caseInsensitive)
            if let match = regex.firstMatch(in: url, options: [], range: NSRange(location: 0, length: url.count)) {
                if let hostRange = Range(match.range(at: 1), in: url),
                    let ownerRange = Range(match.range(at: 2), in: url),
                    let repoRange = Range(match.range(at: 3), in: url) {
                    let host = String(url[hostRange])
                    let owner = String(url[ownerRange])
                    let repo = String(url[repoRange])

                    return URL(string: "https://api.\(host)/repos/\(owner)/\(repo)")
                }
            }
            return nil
        } catch {
            return nil
        }
    }

    private func makeRequestOptions(validResponseCodes: [Int]) -> HTTPClientRequest.Options {
        var options = HTTPClientRequest.Options()
        options.addUserAgent = true
        options.validResponseCodes = validResponseCodes
        options.authorizationProvider = { url in
            url.host.flatMap { host in
                self.configuration.authTokens?[.github(host)].flatMap { token in
                    "token \(token)"
                }
            }
        }
        return options
    }

    private static func makeDefaultHTTPClient(diagnosticsEngine: DiagnosticsEngine?) -> HTTPClient {
        var client = HTTPClient(diagnosticsEngine: diagnosticsEngine)
        // TODO: make these defaults configurable?
        client.configuration.requestTimeout = .seconds(1)
        client.configuration.retryStrategy = .exponentialBackoff(maxAttempts: 3, baseDelay: .milliseconds(50))
        client.configuration.circuitBreakerStrategy = .hostErrors(maxErrors: 50, age: .seconds(30))
        return client
    }

    public struct Configuration {
        public var apiLimitWarningThreshold: Int
        public var authTokens: [AuthTokenType: String]?
        public var cacheDir: AbsolutePath
        public var cacheSizeInMegabytes: Int
        public var cacheTTLInSeconds: Int

        public init(authTokens: [AuthTokenType: String]? = nil,
                    apiLimitWarningThreshold: Int? = nil,
                    cacheDir: AbsolutePath? = nil,
                    cacheTTLInSeconds: Int? = nil,
                    cacheSizeInMegabytes: Int? = nil) {
            self.authTokens = authTokens
            self.apiLimitWarningThreshold = apiLimitWarningThreshold ?? 5
            self.cacheDir = cacheDir.map(resolveSymlinks) ?? localFileSystem.swiftPMCacheDirectory.appending(components: "package-metadata")
            self.cacheSizeInMegabytes = cacheSizeInMegabytes ?? 10
            self.cacheTTLInSeconds = cacheTTLInSeconds ?? 3600
        }
    }

    enum Errors: Error, Equatable {
        case invalidReferenceType(PackageReference)
        case invalidGitURL(String)
        case invalidResponse(URL, String)
        case permissionDenied(URL)
        case invalidAuthToken(URL)
        case apiLimitsExceeded(URL, Int)
    }

    struct CacheValue: Codable {
        let package: Model.PackageBasicMetadata
        let timestamp: UInt64

        var dispatchTime: DispatchTime {
            DispatchTime(uptimeNanoseconds: self.timestamp)
        }

        init(package: Model.PackageBasicMetadata, timestamp: DispatchTime) {
            self.package = package
            self.timestamp = timestamp.uptimeNanoseconds
        }
    }
}

extension GitHubPackageMetadataProvider {
    fileprivate struct GetRepositoryResponse: Codable {
        let name: String
        let fullName: String
        let description: String?
        let topics: [String]?
        let isPrivate: Bool
        let isFork: Bool
        let defaultBranch: String
        let updatedAt: Date
        let sshURL: Foundation.URL
        let cloneURL: Foundation.URL
        let tagsURL: Foundation.URL
        let contributorsURL: Foundation.URL
        let language: String?
        let watchersCount: Int
        let forksCount: Int

        private enum CodingKeys: String, CodingKey {
            case name
            case fullName = "full_name"
            case description
            case topics
            case isPrivate = "private"
            case isFork = "fork"
            case defaultBranch = "default_branch"
            case updatedAt = "updated_at"
            case sshURL = "ssh_url"
            case cloneURL = "clone_url"
            case tagsURL = "tags_url"
            case contributorsURL = "contributors_url"
            case language
            case watchersCount = "watchers_count"
            case forksCount = "forks_count"
        }
    }
}

extension GitHubPackageMetadataProvider {
    fileprivate struct Release: Codable {
        let name: String
        let tagName: String?
        // This might contain rich-text
        let body: String?
        let createdAt: Date
        let publishedAt: Date?

        private enum CodingKeys: String, CodingKey {
            case name
            case tagName = "tag_name"
            case body
            case createdAt = "created_at"
            case publishedAt = "published_at"
        }
    }

    fileprivate struct Tag: Codable {
        let name: String
        let tarballURL: Foundation.URL
        let commit: Commit

        private enum CodingKeys: String, CodingKey {
            case name
            case tarballURL = "tarball_url"
            case commit
        }
    }

    fileprivate struct Commit: Codable {
        let sha: String
        let url: Foundation.URL
    }

    fileprivate struct Contributor: Codable {
        let login: String
        let url: Foundation.URL
        let contributions: Int
    }

    fileprivate struct Readme: Codable {
        let url: Foundation.URL
        let htmlURL: Foundation.URL
        let downloadURL: Foundation.URL

        private enum CodingKeys: String, CodingKey {
            case url
            case htmlURL = "html_url"
            case downloadURL = "download_url"
        }
    }

    fileprivate struct License: Codable {
        let url: Foundation.URL
        let htmlURL: Foundation.URL
        let downloadURL: Foundation.URL
        let license: License

        private enum CodingKeys: String, CodingKey {
            case url
            case htmlURL = "html_url"
            case downloadURL = "download_url"
            case license
        }

        fileprivate struct License: Codable {
            let name: String
            let spdxID: String

            private enum CodingKeys: String, CodingKey {
                case name
                case spdxID = "spdx_id"
            }
        }
    }
}
