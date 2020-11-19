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
    let httpClient: HTTPClient
    let defaultHttpClient: Bool
    let decoder: JSONDecoder
    let queue: DispatchQueue

    init(httpClient: HTTPClient? = nil) {
        self.httpClient = httpClient ?? .init()
        self.defaultHttpClient = httpClient == nil
        self.decoder = JSONDecoder()
        #if os(Linux) || os(Windows)
        self.decoder.dateDecodingStrategy = .iso8601
        #else
        if #available(macOS 10.12, iOS 10.0, watchOS 3.0, tvOS 10.0, *) {
            self.decoder.dateDecodingStrategy = .iso8601
        } else {
            self.decoder.dateDecodingStrategy = .customISO8601
        }
        #endif
        self.queue = DispatchQueue(label: "org.swift.swiftpm.GitHubPackageMetadataProvider", attributes: .concurrent)
    }

    func get(_ reference: PackageReference, callback: @escaping (Result<PackageCollectionsModel.PackageBasicMetadata, Error>) -> Void) {
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

        self.queue.async {
            let sync = DispatchGroup()
            var results = [URL: Result<HTTPClientResponse, Error>]()
            let resultsLock = Lock()

            // get the main data
            sync.enter()
            let options = self.makeRequestOptions(validResponseCodes: [200])
            var headers = HTTPClientHeaders()
            headers.add(name: "Accept", value: "application/vnd.github.mercy-preview+json")
            httpClient.get(metadataURL, headers: headers, options: options) { result in
                defer { sync.leave() }
                resultsLock.withLock {
                    results[metadataURL] = result
                }
                // if successful, fan out multiple API calls
                if case .success = result {
                    [tagsURL, contributorsURL, readmeURL].forEach { url in
                        sync.enter()
                        httpClient.get(url, options: options) { result in
                            defer { sync.leave() }
                            resultsLock.withLock {
                                results[url] = result
                            }
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
                    throw Errors.invalidResponse(metadataURL)
                case .some(.failure(let error)) where error as? HTTPClientError == .badResponseStatusCode(404):
                    throw NotFoundError("\(baseURL)")
                case .some(.failure(let error)):
                    throw error
                case .some(.success(let metadataResponse)):
                    guard let metadata = try metadataResponse.decodeBody(GetRepositoryResponse.self, using: self.decoder) else {
                        throw Errors.invalidResponse(metadataURL)
                    }
                    let tags = try results[tagsURL]?.success?.decodeBody([Tag].self, using: self.decoder) ?? []
                    let contributors = try results[contributorsURL]?.success?.decodeBody([Contributor].self, using: self.decoder)
                    let readme = try results[readmeURL]?.success?.decodeBody(Readme.self, using: self.decoder)

                    callback(.success(.init(
                        description: metadata.description,
                        keywords: metadata.topics,
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
        if defaultHttpClient {
            // TODO: make these defaults configurable?
            options.timeout = httpClient.configuration.requestTimeout ?? .seconds(1)
            options.retryStrategy = httpClient.configuration.retryStrategy ?? .exponentialBackoff(maxAttempts: 3, baseDelay: .milliseconds(50))
            options.circuitBreakerStrategy = httpClient.configuration.circuitBreakerStrategy ?? .hostErrors(maxErrors: 5, age: .seconds(5))
        } else {
            options.timeout = httpClient.configuration.requestTimeout
            options.retryStrategy = httpClient.configuration.retryStrategy
            options.circuitBreakerStrategy = httpClient.configuration.circuitBreakerStrategy
        }
        return options
    }

    enum Errors: Error, Equatable {
        case invalidReferenceType(PackageReference)
        case invalidGitUrl(String)
        case invalidResponse(URL)
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
