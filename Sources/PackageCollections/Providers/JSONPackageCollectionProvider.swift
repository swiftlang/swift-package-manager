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
import struct Foundation.URL
import PackageModel
import SourceControl

struct JSONPackageCollectionProvider: PackageCollectionProvider {
    let configuration: Configuration
    let httpClient: HTTPClient
    let defaultHttpClient: Bool
    let decoder: JSONDecoder

    init(configuration: Configuration = .init(), httpClient: HTTPClient? = nil) {
        self.configuration = configuration
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
    }

    func get(_ source: PackageCollectionsModel.CollectionSource, callback: @escaping (Result<PackageCollectionsModel.Collection, Error>) -> Void) {
        guard case .json = source.type else {
            preconditionFailure("JSONPackageCollectionProvider can only be used for fetching 'json' package collections")
        }

        if let errors = source.validate() {
            return callback(.failure(MultipleErrors(errors)))
        }

        // first do a head request to check content size compared to the maximumSizeInBytes constraint
        let headOptions = self.makeRequestOptions(validResponseCodes: [200])
        self.httpClient.head(source.url, options: headOptions) { result in
            switch result {
            case .failure(let error):
                callback(.failure(error))
            case .success(let response):
                if let contentLength = response.headers.get("Content-Length").first.flatMap(Int.init),
                    contentLength >= self.configuration.maximumSizeInBytes {
                    return callback(.failure(Errors.responseTooLarge(contentLength)))
                }
                // next do a get request to get the actual content
                let getOptions = self.makeRequestOptions(validResponseCodes: [200])
                self.httpClient.get(source.url, options: getOptions) { result in
                    switch result {
                    case .failure(let error):
                        callback(.failure(error))
                    case .success(let response):
                        // check content length again so we can record this as a bad actor
                        // if not returning head and exceeding size
                        // TODO: store bad actors to prevent server DoS
                        guard let contentLength = response.headers.get("Content-Length").first.flatMap(Int.init) else {
                            return callback(.failure(Errors.invalidResponse("Missing Content-Length header")))
                        }
                        guard contentLength < self.configuration.maximumSizeInBytes else {
                            return callback(.failure(Errors.responseTooLarge(contentLength)))
                        }
                        // construct result
                        callback(makeCollection(response))
                    }
                }
            }
        }

        func makeCollection(_ response: HTTPClientResponse) -> Result<PackageCollectionsModel.Collection, Error> {
            let collection: CollectionV1
            do {
                // parse json
                guard let decoded = try response.decodeBody(CollectionV1.self, using: self.decoder) else {
                    throw Errors.invalidResponse("Invalid body")
                }
                collection = decoded
            } catch {
                return .failure(Errors.invalidJSON(error))
            }

            let packages = collection.packages.map { package -> PackageCollectionsModel.Package in
                let versions = package.versions.compactMap { version -> PackageCollectionsModel.Package.Version? in
                    // note this filters out / ignores missing / bad data in attempt to make the most out of the provided set
                    guard let parsedVersion = TSCUtility.Version(string: version.version) else {
                        return nil
                    }
                    guard let toolsVersion = ToolsVersion(string: version.toolsVersion) else {
                        return nil
                    }
                    let targets = version.targets.map { PackageCollectionsModel.Target(name: $0.name, moduleName: $0.moduleName) }
                    let products = version.products.compactMap { PackageCollectionsModel.Product(from: $0, packageTargets: targets) }
                    let verifiedPlatforms: [PackageModel.Platform]? = version.verifiedPlatforms?.compactMap { PackageModel.Platform(from: $0) }
                    let verifiedSwiftVersions = version.verifiedSwiftVersions?.compactMap { SwiftLanguageVersion(string: $0) }
                    let license = version.license.flatMap { PackageCollectionsModel.License(from: $0) }
                    return .init(version: parsedVersion,
                                 packageName: version.packageName,
                                 targets: targets,
                                 products: products,
                                 toolsVersion: toolsVersion,
                                 verifiedPlatforms: verifiedPlatforms,
                                 verifiedSwiftVersions: verifiedSwiftVersions,
                                 license: license)
                }
                return .init(repository: RepositorySpecifier(url: package.url),
                             description: package.description,
                             keywords: package.keywords,
                             versions: versions,
                             latestVersion: versions.first,
                             watchersCount: nil,
                             readmeURL: package.readmeURL.flatMap { Foundation.URL(string: $0) },
                             authors: nil)
            }
            return .success(.init(source: source,
                                  name: collection.name,
                                  description: collection.description,
                                  keywords: collection.keywords,
                                  packages: packages,
                                  createdAt: collection.generatedAt,
                                  lastProcessedAt: Date()))
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

    public struct Configuration {
        public var maximumSizeInBytes: Int

        public init(maximumSizeInBytes: Int? = nil) {
            // TODO: where should we read defaults from?
            self.maximumSizeInBytes = maximumSizeInBytes ?? 5_000_000 // 5MB
        }
    }

    public enum Errors: Error {
        case invalidJSON(Error)
        case invalidResponse(String)
        case responseTooLarge(Int)
    }
}

// MARK: - JSON Models

extension JSONPackageCollectionProvider {
    fileprivate struct CollectionV1: Decodable {
        let name: String
        let description: String?
        let keywords: [String]?
        let formatVersion: String
        let revision: Int?
        let packages: [Package]
        let generatedAt: Date
        let generatedBy: Author?
    }
}

extension JSONPackageCollectionProvider.CollectionV1 {
    fileprivate struct Package: Decodable {
        let url: String
        let description: String?
        let keywords: [String]?
        let versions: [Version]
        let readmeURL: String?
    }

    fileprivate struct Version: Decodable {
        let version: String
        let packageName: String
        let toolsVersion: String
        let targets: [Target]
        let products: [Product]
        let minimumPlatformVersions: [PlatformVersion]?
        let verifiedPlatforms: [Platform]?
        let verifiedSwiftVersions: [String]?
        let license: License?
    }

    fileprivate struct Target: Decodable {
        let name: String
        let moduleName: String?
    }

    fileprivate struct Product: Decodable {
        let name: String
        let type: ProductType
        let targets: [String]
    }

    fileprivate struct Platform: Decodable {
        let name: String
    }

    fileprivate struct License: Decodable {
        let name: String
        let url: String
    }

    fileprivate struct Author: Decodable {
        let name: String
    }
}

// MARK: - Extensions for mapping from JSON to PackageCollectionsModel

extension PackageCollectionsModel.Product {
    fileprivate init?(from: JSONPackageCollectionProvider.CollectionV1.Product, packageTargets: [PackageCollectionsModel.Target]) {
        let targets = packageTargets.filter { from.targets.map { $0.lowercased() }.contains($0.name.lowercased()) }
        self = .init(name: from.name, type: from.type, targets: targets)
    }
}

extension PackageModel.Platform {
    fileprivate init?(from: JSONPackageCollectionProvider.CollectionV1.Platform) {
        switch from.name.lowercased() {
        case let name where name.contains("macos"):
            self = PackageModel.Platform.macOS
        case let name where name.contains("ios"):
            self = PackageModel.Platform.iOS
        case let name where name.contains("tvos"):
            self = PackageModel.Platform.tvOS
        case let name where name.contains("watchos"):
            self = PackageModel.Platform.watchOS
        case let name where name.contains("linux"):
            self = PackageModel.Platform.linux
        case let name where name.contains("android"):
            self = PackageModel.Platform.android
        case let name where name.contains("windows"):
            self = PackageModel.Platform.windows
        case let name where name.contains("wasi"):
            self = PackageModel.Platform.wasi
        default:
            return nil
        }
    }
}

extension PackageCollectionsModel.License {
    fileprivate init?(from: JSONPackageCollectionProvider.CollectionV1.License) {
        let type = PackageCollectionsModel.LicenseType.allCases.first { $0.description.lowercased() == from.name.lowercased() } ?? .other(from.name)
        guard let url = Foundation.URL(string: from.url) else {
            return nil
        }
        self.init(type: type, url: url)
    }
}
