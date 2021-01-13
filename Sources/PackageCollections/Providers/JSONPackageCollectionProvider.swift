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
import TSCBasic

private typealias JSONModel = JSONPackageCollectionModel.V1

struct JSONPackageCollectionProvider: PackageCollectionProvider {
    private let configuration: Configuration
    private let diagnosticsEngine: DiagnosticsEngine?
    private let httpClient: HTTPClient
    private let decoder: JSONDecoder

    init(configuration: Configuration = .init(), httpClient: HTTPClient? = nil, diagnosticsEngine: DiagnosticsEngine? = nil) {
        self.configuration = configuration
        self.diagnosticsEngine = diagnosticsEngine
        self.httpClient = httpClient ?? Self.makeDefaultHTTPClient(diagnosticsEngine: diagnosticsEngine)
        self.decoder = JSONDecoder.makeWithDefaults()
    }

    func get(_ source: Model.CollectionSource, callback: @escaping (Result<Model.Collection, Error>) -> Void) {
        guard case .json = source.type else {
            preconditionFailure("JSONPackageCollectionProvider can only be used for fetching 'json' package collections")
        }

        if let errors = source.validate()?.errors() {
            return callback(.failure(MultipleErrors(errors)))
        }

        // first do a head request to check content size compared to the maximumSizeInBytes constraint
        let headOptions = self.makeRequestOptions(validResponseCodes: [200])
        let headers = self.makeRequestHeaders()
        self.httpClient.head(source.url, headers: headers, options: headOptions) { result in
            switch result {
            case .failure(let error):
                callback(.failure(error))
            case .success(let response):
                guard let contentLength = response.headers.get("Content-Length").first.flatMap(Int.init) else {
                    return callback(.failure(Errors.invalidResponse("Missing Content-Length header")))
                }
                guard contentLength <= self.configuration.maximumSizeInBytes else {
                    return callback(.failure(Errors.responseTooLarge(contentLength)))
                }
                // next do a get request to get the actual content
                let getOptions = self.makeRequestOptions(validResponseCodes: [200])
                self.httpClient.get(source.url, headers: headers, options: getOptions) { result in
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

        func makeCollection(_ response: HTTPClientResponse) -> Result<Model.Collection, Error> {
            let collection: JSONModel.Collection
            do {
                // parse json
                guard let decoded = try response.decodeBody(JSONModel.Collection.self, using: self.decoder) else {
                    throw Errors.invalidResponse("Invalid body")
                }
                collection = decoded
            } catch {
                return .failure(Errors.invalidJSON(error))
            }

            var serializationOkay = true
            let packages = collection.packages.map { package -> Model.Package in
                let versions = package.versions.compactMap { version -> Model.Package.Version? in
                    // note this filters out / ignores missing / bad data in attempt to make the most out of the provided set
                    guard let parsedVersion = TSCUtility.Version(string: version.version) else {
                        return nil
                    }
                    guard let toolsVersion = ToolsVersion(string: version.toolsVersion) else {
                        return nil
                    }
                    let targets = version.targets.map { Model.Target(name: $0.name, moduleName: $0.moduleName) }
                    if targets.count != version.targets.count {
                        serializationOkay = false
                    }
                    let products = version.products.compactMap { Model.Product(from: $0, packageTargets: targets) }
                    if products.count != version.products.count {
                        serializationOkay = false
                    }
                    let minimumPlatformVersions: [PackageModel.SupportedPlatform]? = version.minimumPlatformVersions?.compactMap { PackageModel.SupportedPlatform(from: $0) }
                    if minimumPlatformVersions?.count != version.minimumPlatformVersions?.count {
                        serializationOkay = false
                    }
                    let verifiedCompatibility = version.verifiedCompatibility?.compactMap { Model.Compatibility(from: $0) }
                    if verifiedCompatibility?.count != version.verifiedCompatibility?.count {
                        serializationOkay = false
                    }
                    let license = version.license.flatMap { Model.License(from: $0) }

                    return .init(version: parsedVersion,
                                 packageName: version.packageName,
                                 targets: targets,
                                 products: products,
                                 toolsVersion: toolsVersion,
                                 minimumPlatformVersions: minimumPlatformVersions,
                                 verifiedCompatibility: verifiedCompatibility,
                                 license: license)
                }
                if versions.count != package.versions.count {
                    serializationOkay = false
                }

                return .init(repository: RepositorySpecifier(url: package.url.absoluteString),
                             summary: package.summary,
                             keywords: package.keywords,
                             versions: versions,
                             watchersCount: nil,
                             readmeURL: package.readmeURL,
                             license: package.license.flatMap { Model.License(from: $0) },
                             authors: nil)
            }

            if !serializationOkay {
                self.diagnosticsEngine?.emit(warning: "Some of the information from \(collection.name) could not be deserialized correctly, likely due to invalid format. Contact the collection's author (\(collection.generatedBy?.name ?? "n/a")) to address this issue.")
            }

            return .success(.init(source: source,
                                  name: collection.name,
                                  overview: collection.overview,
                                  keywords: collection.keywords,
                                  packages: packages,
                                  createdAt: collection.generatedAt,
                                  createdBy: collection.generatedBy.flatMap { Model.Collection.Author(name: $0.name) },
                                  lastProcessedAt: Date()))
        }
    }

    private func makeRequestOptions(validResponseCodes: [Int]) -> HTTPClientRequest.Options {
        var options = HTTPClientRequest.Options()
        options.addUserAgent = true
        options.validResponseCodes = validResponseCodes
        return options
    }

    private func makeRequestHeaders() -> HTTPClientHeaders {
        var headers = HTTPClientHeaders()
        // Include "Accept-Encoding" header so we receive "Content-Length" header in the response
        headers.add(name: "Accept-Encoding", value: "*")
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

// MARK: - Extensions for mapping from JSON to PackageCollectionsModel

extension Model.Product {
    fileprivate init(from: JSONModel.Product, packageTargets: [Model.Target]) {
        let targets = packageTargets.filter { from.targets.map { $0.lowercased() }.contains($0.name.lowercased()) }
        self = .init(name: from.name, type: from.type, targets: targets)
    }
}

extension PackageModel.SupportedPlatform {
    fileprivate init?(from: JSONModel.PlatformVersion) {
        guard let platform = Platform(name: from.name) else {
            return nil
        }
        let version = PlatformVersion(from.version)
        self.init(platform: platform, version: version)
    }
}

extension PackageModel.Platform {
    fileprivate init?(from: JSONModel.Platform) {
        self.init(name: from.name)
    }

    fileprivate init?(name: String) {
        switch name.lowercased() {
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

extension Model.Compatibility {
    fileprivate init?(from: JSONModel.Compatibility) {
        guard let platform = PackageModel.Platform(from: from.platform),
            let swiftVersion = SwiftLanguageVersion(string: from.swiftVersion) else {
            return nil
        }
        self.init(platform: platform, swiftVersion: swiftVersion)
    }
}

extension Model.License {
    fileprivate init(from: JSONModel.License) {
        self.init(type: Model.LicenseType(string: from.name), url: from.url)
    }
}
