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
import struct Foundation.URL

import PackageCollectionsModel
import PackageModel
import SourceControl
import TSCBasic

private typealias JSONModel = PackageCollectionModel.V1

struct JSONPackageCollectionProvider: PackageCollectionProvider {
    private let configuration: Configuration
    private let diagnosticsEngine: DiagnosticsEngine?
    private let httpClient: HTTPClient
    private let decoder: JSONDecoder
    private let validator: JSONModel.Validator

    init(configuration: Configuration = .init(), httpClient: HTTPClient? = nil, diagnosticsEngine: DiagnosticsEngine? = nil) {
        self.configuration = configuration
        self.diagnosticsEngine = diagnosticsEngine
        self.httpClient = httpClient ?? Self.makeDefaultHTTPClient(diagnosticsEngine: diagnosticsEngine)
        self.decoder = JSONDecoder.makeWithDefaults()
        self.validator = JSONModel.Validator(configuration: configuration.validator)
    }

    func get(_ source: Model.CollectionSource, callback: @escaping (Result<Model.Collection, Error>) -> Void) {
        guard case .json = source.type else {
            preconditionFailure("JSONPackageCollectionProvider can only be used for fetching 'json' package collections")
        }

        if let errors = source.validate()?.errors() {
            return callback(.failure(MultipleErrors(errors)))
        }

        // Source is a local file
        if let absolutePath = source.absolutePath {
            do {
                let fileContents = try localFileSystem.readFileContents(absolutePath)
                let collection: JSONModel.Collection = try fileContents.withData { data in
                    do {
                        return try self.decoder.decode(JSONModel.Collection.self, from: data)
                    } catch {
                        throw Errors.invalidJSON(error)
                    }
                }
                return callback(self.makeCollection(from: collection, source: source, signature: nil))
            } catch {
                return callback(.failure(error))
            }
        }

        // first do a head request to check content size compared to the maximumSizeInBytes constraint
        let headOptions = self.makeRequestOptions(validResponseCodes: [200])
        let headers = self.makeRequestHeaders()
        self.httpClient.head(source.url, headers: headers, options: headOptions) { result in
            switch result {
            case .failure(let error):
                callback(.failure(error))
            case .success(let response):
                guard let contentLength = response.headers.get("Content-Length").first.flatMap(Int64.init) else {
                    return callback(.failure(Errors.invalidResponse("Missing Content-Length header")))
                }
                guard contentLength <= self.configuration.maximumSizeInBytes else {
                    return callback(.failure(HTTPClientError.responseTooLarge(contentLength)))
                }
                // next do a get request to get the actual content
                var getOptions = self.makeRequestOptions(validResponseCodes: [200])
                getOptions.maximumResponseSizeInBytes = self.configuration.maximumSizeInBytes
                self.httpClient.get(source.url, headers: headers, options: getOptions) { result in
                    switch result {
                    case .failure(let error):
                        callback(.failure(error))
                    case .success(let response):
                        // check content length again so we can record this as a bad actor
                        // if not returning head and exceeding size
                        // TODO: store bad actors to prevent server DoS
                        guard let contentLength = response.headers.get("Content-Length").first.flatMap(Int64.init) else {
                            return callback(.failure(Errors.invalidResponse("Missing Content-Length header")))
                        }
                        guard contentLength < self.configuration.maximumSizeInBytes else {
                            return callback(.failure(HTTPClientError.responseTooLarge(contentLength)))
                        }
                        guard let body = response.body else {
                            return callback(.failure(Errors.invalidResponse("Body is empty")))
                        }

                        do {
                            // parse json and construct result
                            do {
                                // This fails if "signature" is missing
                                let signature = try JSONModel.SignedCollection.signature(from: body, using: self.decoder)
                                // TODO: Check collection's signature
                                // If signature is
                                //      a. valid: process the collection; set isSigned=true
                                //      b. invalid: includes expired cert, untrusted cert, signature-payload mismatch => return error
                                let collection = try JSONModel.SignedCollection.collection(from: body, using: self.decoder)
                                callback(self.makeCollection(from: collection, source: source, signature: Model.SignatureData(from: signature)))
                            } catch {
                                // Collection is not signed
                                guard let collection = try response.decodeBody(JSONModel.Collection.self, using: self.decoder) else {
                                    return callback(.failure(Errors.invalidResponse("Invalid body")))
                                }
                                callback(self.makeCollection(from: collection, source: source, signature: nil))
                            }
                        } catch {
                            callback(.failure(Errors.invalidJSON(error)))
                        }
                    }
                }
            }
        }
    }

    private func makeCollection(from collection: JSONModel.Collection, source: Model.CollectionSource, signature: Model.SignatureData?) -> Result<Model.Collection, Error> {
        if let errors = self.validator.validate(collection: collection)?.errors() {
            return .failure(MultipleErrors(errors))
        }

        var serializationOkay = true
        let packages = collection.packages.map { package -> Model.Package in
            let versions = package.versions.compactMap { version -> Model.Package.Version? in
                // note this filters out / ignores missing / bad data in attempt to make the most out of the provided set
                guard let parsedVersion = TSCUtility.Version(string: version.version) else {
                    return nil
                }

                let manifests = [ToolsVersion: Model.Package.Version.Manifest](uniqueKeysWithValues: version.manifests.compactMap { key, value in
                    guard let keyToolsVersion = ToolsVersion(string: key), let manifestToolsVersion = ToolsVersion(string: value.toolsVersion) else {
                        return nil
                    }

                    let targets = value.targets.map { Model.Target(name: $0.name, moduleName: $0.moduleName) }
                    if targets.count != value.targets.count {
                        serializationOkay = false
                    }
                    let products = value.products.compactMap { Model.Product(from: $0, packageTargets: targets) }
                    if products.count != value.products.count {
                        serializationOkay = false
                    }
                    let minimumPlatformVersions: [PackageModel.SupportedPlatform]? = value.minimumPlatformVersions?.compactMap { PackageModel.SupportedPlatform(from: $0) }
                    if minimumPlatformVersions?.count != value.minimumPlatformVersions?.count {
                        serializationOkay = false
                    }

                    let manifest = Model.Package.Version.Manifest(
                        toolsVersion: manifestToolsVersion,
                        packageName: value.packageName,
                        targets: targets,
                        products: products,
                        minimumPlatformVersions: minimumPlatformVersions
                    )
                    return (keyToolsVersion, manifest)
                })
                if manifests.count != version.manifests.count {
                    serializationOkay = false
                }

                guard let defaultToolsVersion = ToolsVersion(string: version.defaultToolsVersion) else {
                    return nil
                }

                let verifiedCompatibility = version.verifiedCompatibility?.compactMap { Model.Compatibility(from: $0) }
                if verifiedCompatibility?.count != version.verifiedCompatibility?.count {
                    serializationOkay = false
                }
                let license = version.license.flatMap { Model.License(from: $0) }

                return .init(version: parsedVersion,
                             manifests: manifests,
                             defaultToolsVersion: defaultToolsVersion,
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
                              signature: signature,
                              lastProcessedAt: Date()))
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
        public var maximumSizeInBytes: Int64
        public var validator: PackageCollectionModel.V1.Validator.Configuration

        public var maximumPackageCount: Int {
            get {
                self.validator.maximumPackageCount
            }
            set(newValue) {
                self.validator.maximumPackageCount = newValue
            }
        }

        public var maximumMajorVersionCount: Int {
            get {
                self.validator.maximumMajorVersionCount
            }
            set(newValue) {
                self.validator.maximumMajorVersionCount = newValue
            }
        }

        public var maximumMinorVersionCount: Int {
            get {
                self.validator.maximumMinorVersionCount
            }
            set(newValue) {
                self.validator.maximumMinorVersionCount = newValue
            }
        }

        public init(maximumSizeInBytes: Int64? = nil,
                    maximumPackageCount: Int? = nil,
                    maximumMajorVersionCount: Int? = nil,
                    maximumMinorVersionCount: Int? = nil) {
            // TODO: where should we read defaults from?
            self.maximumSizeInBytes = maximumSizeInBytes ?? 5_000_000 // 5MB
            self.validator = JSONModel.Validator.Configuration(
                maximumPackageCount: maximumPackageCount,
                maximumMajorVersionCount: maximumMajorVersionCount,
                maximumMinorVersionCount: maximumMinorVersionCount
            )
        }
    }

    public enum Errors: Error {
        case invalidJSON(Error)
        case invalidResponse(String)
    }
}

// MARK: - Extensions for mapping from JSON to PackageCollectionsModel

extension Model.Product {
    fileprivate init(from: JSONModel.Product, packageTargets: [Model.Target]) {
        let targets = packageTargets.filter { from.targets.map { $0.lowercased() }.contains($0.name.lowercased()) }
        self = .init(name: from.name, type: .init(from: from.type), targets: targets)
    }
}

extension PackageModel.ProductType {
    fileprivate init(from: JSONModel.ProductType) {
        switch from {
        case .library(let libraryType):
            self = .library(.init(from: libraryType))
        case .executable:
            self = .executable
        case .test:
            self = .test
        }
    }
}

extension PackageModel.ProductType.LibraryType {
    fileprivate init(from: JSONModel.ProductType.LibraryType) {
        switch from {
        case .static:
            self = .static
        case .dynamic:
            self = .dynamic
        case .automatic:
            self = .automatic
        }
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

extension Model.SignatureData {
    fileprivate init(from: JSONModel.Signature) {
        self.certificate = .init(from: from.certificate)
    }
}

extension Model.SignatureData.Certificate {
    fileprivate init(from: JSONModel.Signature.Certificate) {
        self.subject = .init(from: from.subject)
        self.issuer = .init(from: from.issuer)
    }
}

extension Model.SignatureData.Certificate.Name {
    fileprivate init(from: JSONModel.Signature.Certificate.Name) {
        self.commonName = from.commonName
    }
}
