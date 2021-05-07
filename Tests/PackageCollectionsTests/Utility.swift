/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020-2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import struct Foundation.Date
import struct Foundation.URL
import struct Foundation.UUID

@testable import PackageCollections
import PackageCollectionsModel
import PackageCollectionsSigning
import PackageModel
import SourceControl
import TSCBasic
import TSCUtility

func makeMockSources(count: Int = Int.random(in: 5 ... 10)) -> [PackageCollectionsModel.CollectionSource] {
    let isTrusted: [Bool?] = [true, false, nil]
    return (0 ..< count).map { index in
        .init(type: .json, url: URL(string: "https://source-\(index)")!, isTrusted: isTrusted.randomElement()!)
    }
}

func makeMockCollections(count: Int = Int.random(in: 50 ... 100), maxPackages: Int = 50, signed: Bool = true) -> [PackageCollectionsModel.Collection] {
    let platforms: [PackageModel.Platform] = [.macOS, .iOS, .tvOS, .watchOS, .linux, .android, .windows, .wasi]
    let supportedPlatforms: [PackageModel.SupportedPlatform] = [
        .init(platform: .macOS, version: .init("10.15")),
        .init(platform: .iOS, version: .init("13")),
        .init(platform: .watchOS, version: "6"),
    ]

    return (0 ..< count).map { collectionIndex in
        let packages = (0 ..< Int.random(in: min(5, maxPackages) ... maxPackages)).map { packageIndex -> PackageCollectionsModel.Package in
            let versions = (0 ..< Int.random(in: 1 ... 3)).map { versionIndex -> PackageCollectionsModel.Package.Version in
                let targets = (0 ..< Int.random(in: 1 ... 5)).map {
                    PackageCollectionsModel.Target(name: "package-\(packageIndex)-target-\($0)",
                                                   moduleName: "module-package-\(packageIndex)-target-\($0)")
                }
                let products = (0 ..< Int.random(in: 1 ... 3)).map {
                    PackageCollectionsModel.Product(name: "package-\(packageIndex)-product-\($0)",
                                                    type: .executable,
                                                    targets: targets)
                }
                let minimumPlatformVersions = (0 ..< Int.random(in: 1 ... 2)).map { _ in supportedPlatforms.randomElement()! }
                let toolsVersion = ToolsVersion(string: "5.2")!
                let manifests = [toolsVersion: PackageCollectionsModel.Package.Version.Manifest(
                    toolsVersion: toolsVersion,
                    packageName: "package-\(packageIndex)",
                    targets: targets,
                    products: products,
                    minimumPlatformVersions: minimumPlatformVersions
                )]

                let verifiedCompatibility = (0 ..< Int.random(in: 1 ... 3)).map { _ in
                    PackageCollectionsModel.Compatibility(
                        platform: platforms.randomElement()!,
                        swiftVersion: SwiftLanguageVersion.knownSwiftLanguageVersions.randomElement()!
                    )
                }
                let licenseType = PackageCollectionsModel.LicenseType.allCases.randomElement()!
                let license = PackageCollectionsModel.License(type: licenseType, url: URL(string: "http://\(licenseType).license")!)

                return PackageCollectionsModel.Package.Version(version: TSCUtility.Version(versionIndex, 0, 0),
                                                               title: nil,
                                                               summary: "\(versionIndex) description",
                                                               manifests: manifests,
                                                               defaultToolsVersion: toolsVersion,
                                                               verifiedCompatibility: verifiedCompatibility,
                                                               license: license,
                                                               createdAt: Date())
            }

            return PackageCollectionsModel.Package(repository: RepositorySpecifier(url: "https://package-\(packageIndex)"),
                                                   summary: "package \(packageIndex) description",
                                                   keywords: (0 ..< Int.random(in: 1 ... 3)).map { "keyword \($0)" },
                                                   versions: versions,
                                                   watchersCount: Int.random(in: 1 ... 1000),
                                                   readmeURL: URL(string: "https://package-\(packageIndex)-readme")!,
                                                   license: PackageCollectionsModel.License(type: .Apache2_0, url: URL(string: "https://\(packageIndex).license")!),
                                                   authors: nil,
                                                   languages: nil)
        }

        var signature: PackageCollectionsModel.SignatureData?
        if signed {
            signature = .init(
                certificate: PackageCollectionsModel.SignatureData.Certificate(
                    subject: .init(userID: nil, commonName: "subject-\(collectionIndex)", organizationalUnit: nil, organization: nil),
                    issuer: .init(userID: nil, commonName: "issuer-\(collectionIndex)", organizationalUnit: nil, organization: nil)
                ),
                isVerified: true
            )
        }

        return PackageCollectionsModel.Collection(source: .init(type: .json, url: URL(string: "https://feed-\(collectionIndex)")!),
                                                  name: "collection \(collectionIndex)",
                                                  overview: "collection \(collectionIndex) description",
                                                  keywords: (0 ..< Int.random(in: 1 ... 3)).map { "keyword \($0)" },
                                                  packages: packages,
                                                  createdAt: Date(),
                                                  createdBy: PackageCollectionsModel.Collection.Author(name: "Jane Doe"),
                                                  signature: signature)
    }
}

func makeMockPackageBasicMetadata() -> PackageCollectionsModel.PackageBasicMetadata {
    return .init(summary: UUID().uuidString,
                 keywords: (0 ..< Int.random(in: 1 ... 3)).map { "keyword \($0)" },
                 versions: (0 ..< Int.random(in: 1 ... 10)).map { .init(version: TSCUtility.Version($0, 0, 0), title: "title \($0)", summary: "description \($0)", createdAt: Date(), publishedAt: nil) },
                 watchersCount: Int.random(in: 0 ... 50),
                 readmeURL: URL(string: "https://package-readme")!,
                 license: PackageCollectionsModel.License(type: .Apache2_0, url: URL(string: "https://package-license")!),
                 authors: (0 ..< Int.random(in: 1 ... 10)).map { .init(username: "\($0)", url: nil, service: nil) },
                 languages: ["Swift"],
                 processedAt: Date())
}

func makeMockStorage() -> PackageCollections.Storage {
    let mockFileSystem = InMemoryFileSystem()
    return .init(sources: FilePackageCollectionsSourcesStorage(fileSystem: mockFileSystem),
                 collections: SQLitePackageCollectionsStorage(location: .memory))
}

struct MockCollectionsProvider: PackageCollectionProvider {
    let collections: [PackageCollectionsModel.Collection]
    let collectionsWithInvalidSignature: Set<PackageCollectionsModel.CollectionSource>?

    init(_ collections: [PackageCollectionsModel.Collection], collectionsWithInvalidSignature: Set<PackageCollectionsModel.CollectionSource>? = nil) {
        self.collections = collections
        self.collectionsWithInvalidSignature = collectionsWithInvalidSignature
    }

    func get(_ source: PackageCollectionsModel.CollectionSource, callback: @escaping (Result<PackageCollectionsModel.Collection, Error>) -> Void) {
        if let collection = (self.collections.first { $0.source == source }) {
            if self.collectionsWithInvalidSignature?.contains(source) ?? false {
                return callback(.failure(PackageCollectionError.invalidSignature))
            }
            callback(.success(collection))
        } else {
            callback(.failure(NotFoundError("\(source)")))
        }
    }
}

struct MockMetadataProvider: PackageMetadataProvider {
    var name: String = "MockMetadataProvider"

    let packages: [PackageReference: PackageCollectionsModel.PackageBasicMetadata]

    init(_ packages: [PackageReference: PackageCollectionsModel.PackageBasicMetadata]) {
        self.packages = packages
    }

    func get(_ reference: PackageReference, callback: @escaping (Result<PackageCollectionsModel.PackageBasicMetadata, Error>) -> Void) {
        if let package = self.packages[reference] {
            callback(.success(package))
        } else {
            callback(.failure(NotFoundError("\(reference)")))
        }
    }

    func getAuthTokenType(for reference: PackageReference) -> AuthTokenType? {
        nil
    }

    func close() throws {}
}

struct MockCollectionSignatureValidator: PackageCollectionSignatureValidator {
    let collections: Set<String>
    let hasTrustedRootCerts: Bool

    init(_ collections: Set<String> = [], hasTrustedRootCerts: Bool = true) {
        self.collections = collections
        self.hasTrustedRootCerts = hasTrustedRootCerts
    }

    func validate(signedCollection: PackageCollectionModel.V1.SignedCollection,
                  certPolicyKey: CertificatePolicyKey,
                  callback: @escaping (Result<Void, Error>) -> Void) {
        guard self.hasTrustedRootCerts else {
            return callback(.failure(PackageCollectionSigningError.noTrustedRootCertsConfigured))
        }

        if self.collections.contains(signedCollection.collection.name) {
            callback(.success(()))
        } else {
            callback(.failure(PackageCollectionSigningError.invalidSignature))
        }
    }
}
