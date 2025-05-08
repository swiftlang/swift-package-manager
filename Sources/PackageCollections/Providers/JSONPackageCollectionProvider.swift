//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import _Concurrency

import Basics
import Dispatch
import struct Foundation.Data
import struct Foundation.Date
import class Foundation.JSONDecoder
import class Foundation.ProcessInfo
import struct Foundation.URL

import PackageCollectionsModel
import PackageCollectionsSigning
import PackageModel
import SourceControl
import TSCBasic

import struct TSCUtility.Version

private typealias JSONModel = PackageCollectionModel.V1

struct JSONPackageCollectionProvider: PackageCollectionProvider {
    // TODO: This can be removed when the `Security` framework APIs that the `PackageCollectionsSigning`
    // module depends on are available on all Apple platforms.
    #if os(macOS) || os(Linux) || os(Windows) || os(Android) || os(FreeBSD)
    static let isSignatureCheckSupported = true
    #else
    static let isSignatureCheckSupported = false
    #endif

    static let defaultCertPolicyKeys: [CertificatePolicyKey] = [.default]

    private let configuration: Configuration
    private let fileSystem: FileSystem
    private let observabilityScope: ObservabilityScope
    private let httpClient: LegacyHTTPClient
    private let decoder: JSONDecoder
    private let validator: JSONModel.Validator
    private let signatureValidator: PackageCollectionSignatureValidator
    private let sourceCertPolicy: PackageCollectionSourceCertificatePolicy

    init(
        configuration: Configuration = .init(),
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        sourceCertPolicy: PackageCollectionSourceCertificatePolicy = PackageCollectionSourceCertificatePolicy(),
        customHTTPClient: LegacyHTTPClient? = nil,
        customSignatureValidator: PackageCollectionSignatureValidator? = nil
    ) {
        self.configuration = configuration
        self.validator = JSONModel.Validator(configuration: configuration.validator)
        self.fileSystem = fileSystem
        self.observabilityScope = observabilityScope
        self.httpClient = customHTTPClient ?? Self.makeDefaultHTTPClient()
        self.signatureValidator = customSignatureValidator ?? PackageCollectionSigning(
            trustedRootCertsDir: configuration.trustedRootCertsDir ??
                (try? fileSystem.swiftPMConfigurationDirectory.appending("trust-root-certs").asURL) ?? Basics.AbsolutePath.root.asURL,
            additionalTrustedRootCerts: sourceCertPolicy.allRootCerts.map { Array($0) },
            observabilityScope: observabilityScope
        )
        self.sourceCertPolicy = sourceCertPolicy
        self.decoder = JSONDecoder.makeWithDefaults()
    }

    func get(_ source: Model.CollectionSource) async throws -> Model.Collection {
        guard case .json = source.type else {
            throw InternalError(
                "JSONPackageCollectionProvider can only be used for fetching 'json' package collections"
            )
        }

        if let errors = source.validate(fileSystem: fileSystem)?.errors() {
            throw JSONPackageCollectionProviderError.invalidSource("\(errors)")
        }

        // Source is a local file
        if let absolutePath = source.absolutePath {
            let data: Data = try self.fileSystem.readFileContents(absolutePath)
            return try await self.decodeAndRunSignatureCheck(
                source: source,
                data: data,
                certPolicyKeys: Self.defaultCertPolicyKeys
            )
        }

        // first do a head request to check content size compared to the maximumSizeInBytes constraint
        let headOptions = self.makeRequestOptions(validResponseCodes: [200])
        let headers = self.makeRequestHeaders()
        let response: LegacyHTTPClient.Response
        do {
            response = try await self.httpClient.head(source.url, headers: headers, options: headOptions)
        } catch HTTPClientError.badResponseStatusCode(let statusCode) {
            if statusCode == 404 {
                throw JSONPackageCollectionProviderError
                    .collectionNotFound(source.url)
            }
            throw JSONPackageCollectionProviderError
                .collectionUnavailable(source.url, statusCode)
        }
        guard let contentLength = response.headers.get("Content-Length").first.flatMap(Int64.init) else {
            throw JSONPackageCollectionProviderError
                .invalidResponse(source.url, "Missing Content-Length header")
        }
        guard contentLength <= self.configuration.maximumSizeInBytes else {
            throw JSONPackageCollectionProviderError
                .responseTooLarge(source.url, contentLength)
        }
        // next do a get request to get the actual content
        var getOptions = self.makeRequestOptions(validResponseCodes: [200])
        getOptions.maximumResponseSizeInBytes = self.configuration.maximumSizeInBytes

        let getResponse: LegacyHTTPClient.Response
        do {
            getResponse = try await self.httpClient.get(source.url, headers: headers, options: getOptions)
        } catch HTTPClientError.badResponseStatusCode(let statusCode) {
            if statusCode == 404 {
                throw JSONPackageCollectionProviderError
                    .collectionNotFound(source.url)
            }
            throw JSONPackageCollectionProviderError
                .collectionUnavailable(source.url, statusCode)
        }

        // check content length again so we can record this as a bad actor
        // if not returning head and exceeding size
        // TODO: store bad actors to prevent server DoS
        guard let contentLength = getResponse.headers.get("Content-Length").first.flatMap(Int64.init)
        else {
            throw JSONPackageCollectionProviderError
                .invalidResponse(source.url, "Missing Content-Length header")
        }
        guard contentLength < self.configuration.maximumSizeInBytes else {
            throw JSONPackageCollectionProviderError
                .responseTooLarge(source.url, contentLength)
        }
        guard let body = getResponse.body else {
            throw JSONPackageCollectionProviderError
                .invalidResponse(source.url, "Body is empty")
        }

        let certPolicyKeys = self.sourceCertPolicy.certificatePolicyKeys(for: source) ?? Self
            .defaultCertPolicyKeys
        return try await self.decodeAndRunSignatureCheck(
            source: source,
            data: body,
            certPolicyKeys: certPolicyKeys
        )
    }

    private func decodeAndRunSignatureCheck(
        source: Model.CollectionSource,
        data: Data,
        certPolicyKeys: [CertificatePolicyKey]
    ) async throws -> Model.Collection {
        let signedCollection: JSONModel.SignedCollection
        do {
            // This fails if collection is not signed (i.e., no "signature")
            signedCollection = try self.decoder.decode(JSONModel.SignedCollection.self, from: data)
        } catch {
            // Bad: collection is supposed to be signed but it isn't
            guard !self.sourceCertPolicy.mustBeSigned(source: source) else {
                throw PackageCollectionError.missingSignature
            }
            // Collection is unsigned
            guard let collection = try? self.decoder.decode(JSONModel.Collection.self, from: data) else {
                throw JSONPackageCollectionProviderError.invalidJSON(source.url)
            }
            return try self.makeCollection(from: collection, source: source, signature: nil)
        }
        if source.skipSignatureCheck {
            // Don't validate signature; set isVerified=false
            return try self.makeCollection(
                from: signedCollection.collection,
                source: source,
                signature: Model.SignatureData(from: signedCollection.signature, isVerified: false)
            )
        } else if !Self.isSignatureCheckSupported {
            throw StringError("Unsupported platform")
        }
        // Check the signature
        do {
            return try await withThrowingTaskGroup(of: Void.self) { group in
                for certPolicyKey in certPolicyKeys {
                    group.addTask {
                        try await self.signatureValidator.validate(
                            signedCollection: signedCollection,
                            certPolicyKey: certPolicyKey
                        )
                    }
                }

                // if there is one valid key return the validated collection
                // otherwise throw the error for the last key
                var results = 0
                while results < certPolicyKeys.count {
                    results += 1
                    do {
                        try await group.next()
                        break
                    } catch {
                        if results == certPolicyKeys.count {
                            throw error
                        }
                    }
                }
                return try self.makeCollection(
                    from: signedCollection.collection,
                    source: source,
                    signature: Model.SignatureData(from: signedCollection.signature, isVerified: true)
                )
            }
        } catch {
            self.observabilityScope.emit(
                warning: "The signature of package collection [\(source)] is invalid",
                underlyingError: error
            )
            if PackageCollectionSigningError
                .noTrustedRootCertsConfigured == error as? PackageCollectionSigningError
            {
                throw PackageCollectionError.cannotVerifySignature
            } else {
                throw PackageCollectionError.invalidSignature
            }
        }
    }

    private func makeCollection(
        from collection: JSONModel.Collection,
        source: Model.CollectionSource,
        signature: Model.SignatureData?
    ) throws -> Model.Collection {
        if let errors = self.validator.validate(collection: collection)?.errors() {
            throw JSONPackageCollectionProviderError
                .invalidCollection("\(errors.map(\.message).joined(separator: " "))")
        }

        var serializationOkay = true
        let packages = try collection.packages.map { package -> Model.Package in
            let versions = try package.versions.compactMap { version -> Model.Package.Version? in
                // note this filters out / ignores missing / bad data in attempt to make the most out of the
                // provided set
                guard let parsedVersion = TSCUtility.Version(tag: version.version) else {
                    return nil
                }

                let manifests: [ToolsVersion: Model.Package.Version.Manifest] =
                try Dictionary(throwingUniqueKeysWithValues: version.manifests.compactMap { key, value in
                    guard let keyToolsVersion = ToolsVersion(string: key),
                          let manifestToolsVersion = ToolsVersion(string: value.toolsVersion)
                    else {
                        return nil
                    }

                    let targets = value.targets.map { Model.Target(name: $0.name, moduleName: $0.moduleName) }
                    if targets.count != value.targets.count {
                        serializationOkay = false
                    }
                    let products = value.products
                        .compactMap { Model.Product(from: $0, packageTargets: targets) }
                    if products.count != value.products.count {
                        serializationOkay = false
                    }
                    let minimumPlatformVersions: [PackageModel.SupportedPlatform]? = value
                        .minimumPlatformVersions?
                        .compactMap { PackageModel.SupportedPlatform(from: $0) }
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

                let verifiedCompatibility = version.verifiedCompatibility?
                    .compactMap { Model.Compatibility(from: $0) }
                if verifiedCompatibility?.count != version.verifiedCompatibility?.count {
                    serializationOkay = false
                }
                let license = version.license.flatMap { Model.License(from: $0) }

                let signer: Model.Signer?
                if let versionSigner = version.signer,
                   let signerType = Model.SignerType(rawValue: versionSigner.type.lowercased())
                {
                    signer = .init(
                        type: signerType,
                        commonName: versionSigner.commonName,
                        organizationalUnitName: versionSigner.organizationalUnitName,
                        organizationName: versionSigner.organizationName
                    )
                } else {
                    signer = nil
                }

                return .init(
                    version: parsedVersion,
                    title: nil,
                    summary: version.summary,
                    manifests: manifests,
                    defaultToolsVersion: defaultToolsVersion,
                    verifiedCompatibility: verifiedCompatibility,
                    license: license,
                    author: version.author.map { .init(username: $0.name, url: nil, service: nil) },
                    signer: signer,
                    createdAt: version.createdAt
                )
            }
            if versions.count != package.versions.count {
                serializationOkay = false
            }

            // If package identity is set, use that. Otherwise create one from URL.
            return .init(
                identity: package.identity.map { PackageIdentity.plain($0) } ?? PackageIdentity(url: SourceControlURL(package.url)),
                location: package.url.absoluteString,
                summary: package.summary,
                keywords: package.keywords,
                versions: versions,
                watchersCount: nil,
                readmeURL: package.readmeURL,
                license: package.license.flatMap { Model.License(from: $0) },
                authors: nil,
                languages: nil
            )
        }

        if !serializationOkay {
            self.observabilityScope
                .emit(
                    warning: "Some of the information from \(collection.name) could not be deserialized correctly, likely due to invalid format. Contact the collection's author (\(collection.generatedBy?.name ?? "n/a")) to address this issue."
                )
        }

        return .init(
            source: source,
            name: collection.name,
            overview: collection.overview,
            keywords: collection.keywords,
            packages: packages,
            createdAt: collection.generatedAt,
            createdBy: collection.generatedBy.flatMap { Model.Collection.Author(name: $0.name) },
            signature: signature,
            lastProcessedAt: Date()
        )
    }

    private func makeRequestOptions(validResponseCodes: [Int]) -> LegacyHTTPClientRequest.Options {
        var options = LegacyHTTPClientRequest.Options()
        options.addUserAgent = true
        options.validResponseCodes = validResponseCodes
        return options
    }

    private func makeRequestHeaders() -> HTTPClientHeaders {
        var headers = HTTPClientHeaders()
        // Include "Accept-Encoding" header so we receive "Content-Length" header in the response
        headers.add(name: "Accept-Encoding", value: "deflate, identity, gzip;q=0")
        return headers
    }

    private static func makeDefaultHTTPClient() -> LegacyHTTPClient {
        let client = LegacyHTTPClient()
        // TODO: make these defaults configurable?
        client.configuration.requestTimeout = .seconds(5)
        client.configuration.retryStrategy = .exponentialBackoff(maxAttempts: 3, baseDelay: .milliseconds(50))
        client.configuration.circuitBreakerStrategy = .hostErrors(maxErrors: 50, age: .seconds(30))
        return client
    }

    public struct Configuration {
        public var maximumSizeInBytes: Int64
        public var trustedRootCertsDir: URL?

        var validator: PackageCollectionModel.V1.Validator.Configuration

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

        public init(
            maximumSizeInBytes: Int64? = nil,
            trustedRootCertsDir: URL? = nil,
            maximumPackageCount: Int? = nil,
            maximumMajorVersionCount: Int? = nil,
            maximumMinorVersionCount: Int? = nil
        ) {
            // TODO: where should we read defaults from?
            self.maximumSizeInBytes = maximumSizeInBytes ?? 5_000_000 // 5MB
            self.trustedRootCertsDir = trustedRootCertsDir
            self.validator = JSONModel.Validator.Configuration(
                maximumPackageCount: maximumPackageCount,
                maximumMajorVersionCount: maximumMajorVersionCount,
                maximumMinorVersionCount: maximumMinorVersionCount
            )
        }
    }
}

public enum JSONPackageCollectionProviderError: Error, Equatable, CustomStringConvertible {
    case invalidSource(String)
    case invalidJSON(URL)
    case invalidCollection(String)
    case invalidResponse(URL, String)
    case responseTooLarge(URL, Int64)
    case collectionNotFound(URL)
    case collectionUnavailable(URL, Int)

    public var description: String {
        switch self {
        case .invalidSource(let errorMessage), .invalidCollection(let errorMessage):
            return errorMessage
        case .invalidJSON(let url):
            return "The package collection at \(url.absoluteString) contains invalid JSON."
        case .invalidResponse(let url, let message):
            return "Received invalid response for package collection at \(url.absoluteString): \(message)"
        case .responseTooLarge(let url, _):
            return "The package collection at \(url.absoluteString) is too large."
        case .collectionNotFound(let url):
            return "No package collection found at \(url.absoluteString). Please make sure the URL is correct."
        case .collectionUnavailable(let url, _):
            return "The package collection at \(url.absoluteString) is unavailable. Please make sure the URL is correct or try again later."
        }
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
        case .plugin:
            self = .plugin
        case .snippet:
            self = .snippet
        case .test:
            self = .test
        case .macro:
            self = .macro
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
        case let name where name.contains("maccatalyst"):
            self = PackageModel.Platform.macCatalyst
        case let name where name.contains("ios"):
            self = PackageModel.Platform.iOS
        case let name where name.contains("tvos"):
            self = PackageModel.Platform.tvOS
        case let name where name.contains("watchos"):
            self = PackageModel.Platform.watchOS
        case let name where name.contains("visionos"):
            self = PackageModel.Platform.visionOS
        case let name where name.contains("driverkit"):
            self = PackageModel.Platform.driverKit
        case let name where name.contains("linux"):
            self = PackageModel.Platform.linux
        case let name where name.contains("android"):
            self = PackageModel.Platform.android
        case let name where name.contains("windows"):
            self = PackageModel.Platform.windows
        case let name where name.contains("wasi"):
            self = PackageModel.Platform.wasi
        case let name where name.contains("openbsd"):
            self = PackageModel.Platform.openbsd
        case let name where name.contains("freebsd"):
            self = PackageModel.Platform.freebsd
        default:
            return nil
        }
    }
}

extension Model.Compatibility {
    fileprivate init?(from: JSONModel.Compatibility) {
        guard let platform = PackageModel.Platform(from: from.platform),
              let swiftVersion = SwiftLanguageVersion(string: from.swiftVersion)
        else {
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
    fileprivate init(from: JSONModel.Signature, isVerified: Bool) {
        self.certificate = .init(from: from.certificate)
        self.isVerified = isVerified
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
        self.userID = from.userID
        self.commonName = from.commonName
        self.organizationalUnit = from.organizationalUnit
        self.organization = from.organization
    }
}
