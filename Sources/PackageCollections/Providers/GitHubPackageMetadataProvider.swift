/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
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

    init(configuration: Configuration = .init(), httpClient: HTTPClient? = nil, diagnosticsEngine: DiagnosticsEngine? = nil) {
        self.configuration = configuration
        self.httpClient = httpClient ?? Self.makeDefaultHTTPClient(diagnosticsEngine: diagnosticsEngine)
        self.diagnosticsEngine = diagnosticsEngine
        self.decoder = JSONDecoder.makeWithDefaults()
    }

    func get(_ reference: PackageReference, callback: @escaping (Result<Model.PackageBasicMetadata, Error>) -> Void) {
        guard reference.kind == .remote else {
            return callback(.failure(Errors.invalidReferenceType(reference)))
        }
        guard let baseURL = self.apiURL(reference.path) else {
            return callback(.failure(Errors.invalidGitUrl(reference.path)))
        }

        let metadataURL = baseURL
        let tagsURL = baseURL.appendingPathComponent("tags")
        let contributorsURL = baseURL.appendingPathComponent("contributors")
        let readmeURL = baseURL.appendingPathComponent("readme")

        let sync = DispatchGroup()
        var results = [URL: Result<HTTPClientResponse, Error>]()
        let resultsLock = Lock()

        // get the main data
        sync.enter()
        var metadataHeaders = self.makeRequestHeaders(metadataURL)
        metadataHeaders.add(name: "Accept", value: "application/vnd.github.mercy-preview+json")
        let metadataOptions = self.makeRequestOptions(validResponseCodes: [200, 401, 403, 404])
        httpClient.get(metadataURL, headers: metadataHeaders, options: metadataOptions) { result in
            defer { sync.leave() }
            resultsLock.withLock {
                results[metadataURL] = result
            }
            if case .success(let response) = result {
                let apiLimit = response.headers.get("X-RateLimit-Limit").first.flatMap(Int.init) ?? -1
                let apiRemaining = response.headers.get("X-RateLimit-Remaining").first.flatMap(Int.init) ?? -1
                switch (response.statusCode, metadataHeaders.contains("Authorization"), apiRemaining) {
                case (_, _, 0):
                    self.diagnosticsEngine?.emit(warning: "Exceeded API limits on \(metadataURL.host ?? metadataURL.absoluteString) (\(apiRemaining)/\(apiLimit)), consider configuring an API token for this service.")
                    resultsLock.withLock {
                        results[metadataURL] = .failure(Errors.apiLimitsExceeded(metadataURL, apiLimit))
                    }
                case (401, true, _):
                    resultsLock.withLock {
                        results[metadataURL] = .failure(Errors.invalidAuthToken(metadataURL))
                    }
                case (401, false, _):
                    resultsLock.withLock {
                        results[metadataURL] = .failure(Errors.permissionDenied(metadataURL))
                    }
                case (403, _, _):
                    resultsLock.withLock {
                        results[metadataURL] = .failure(Errors.permissionDenied(metadataURL))
                    }
                case (404, _, _):
                    resultsLock.withLock {
                        results[metadataURL] = .failure(NotFoundError("\(baseURL)"))
                    }
                case (200, _, _):
                    if apiRemaining < self.configuration.apiLimitWarningThreshold {
                        self.diagnosticsEngine?.emit(warning: "Approaching API limits on \(metadataURL.host ?? metadataURL.absoluteString) (\(apiRemaining)/\(apiLimit)), consider configuring an API token for this service.")
                    }
                    // if successful, fan out multiple API calls
                    [tagsURL, contributorsURL, readmeURL].forEach { url in
                        sync.enter()
                        var headers = self.makeRequestHeaders(url)
                        headers.add(name: "Accept", value: "application/vnd.github.v3+json")
                        let options = self.makeRequestOptions(validResponseCodes: [200])
                        httpClient.get(url, headers: headers, options: options) { result in
                            defer { sync.leave() }
                            resultsLock.withLock {
                                results[url] = result
                            }
                        }
                    }
                default:
                    resultsLock.withLock {
                        results[metadataURL] = .failure(Errors.invalidResponse(metadataURL, "Invalid status code: \(response.statusCode)"))
                    }
                }
            }
        }
        sync.wait()

        // process results

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
                let tags = try results[tagsURL]?.success?.decodeBody([Tag].self, using: self.decoder) ?? []
                let contributors = try results[contributorsURL]?.success?.decodeBody([Contributor].self, using: self.decoder)
                let readme = try results[readmeURL]?.success?.decodeBody(Readme.self, using: self.decoder)

                callback(.success(.init(
                    summary: metadata.description,
                    keywords: metadata.topics,
                    // filters out non-semantic versioned tags
                    versions: tags.compactMap { TSCUtility.Version(string: $0.name) },
                    watchersCount: metadata.watchersCount,
                    readmeURL: readme?.downloadURL,
                    authors: contributors?.map { .init(username: $0.login, url: $0.url, service: .init(name: "GitHub")) },
                    processedAt: Date()
                )))
            }
        } catch {
            return callback(.failure(error))
        }
    }

    internal func apiURL(_ url: String) -> Foundation.URL? {
        do {
            let regex = try NSRegularExpression(pattern: "([^/@]+)[:/]([^:/]+)/([^/]+)\\.git$", options: .caseInsensitive)
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
        return options
    }

    private func makeRequestHeaders(_ url: URL) -> HTTPClientHeaders {
        var headers = HTTPClientHeaders()
        if let host = url.host, let token = self.configuration.authTokens?[.github(host)] {
            headers.add(name: "Authorization", value: "token \(token)")
        }
        return headers
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

        public init(authTokens: [AuthTokenType: String]? = nil,
                    apiLimitWarningThreshold: Int? = nil) {
            self.authTokens = authTokens
            self.apiLimitWarningThreshold = apiLimitWarningThreshold ?? 5
        }
    }

    enum Errors: Error, Equatable {
        case invalidReferenceType(PackageReference)
        case invalidGitUrl(String)
        case invalidResponse(URL, String)
        case permissionDenied(URL)
        case invalidAuthToken(URL)
        case apiLimitsExceeded(URL, Int)
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
        let license: License?
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
            case license
            case watchersCount = "watchers_count"
            case forksCount = "forks_count"
        }
    }
}

extension GitHubPackageMetadataProvider {
    fileprivate struct License: Codable {
        let key: String
        let name: String
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
}
