/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import struct Foundation.Date
import struct Foundation.URL
import struct Foundation.UUID
@testable import PackageCollections
import PackageModel
import SourceControl
import TSCBasic
import TSCUtility

func makeMockSources(count: Int = Int.random(in: 5 ... 10)) -> [PackageCollectionsModel.CollectionSource] {
    return (0 ..< count).map { index in
        .init(type: .json, url: URL(string: "https://source-\(index)")!)
    }
}

func makeMockCollections(count: Int = Int.random(in: 50 ... 100), maxPackages: Int = 50) -> [PackageCollectionsModel.Collection] {
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
                let verifiedPlatforms = (0 ..< Int.random(in: 1 ... 3)).map { _ in platforms.randomElement()! }
                let verifiedSwiftVersions = (0 ..< Int.random(in: 1 ... 3)).map { _ in SwiftLanguageVersion.knownSwiftLanguageVersions.randomElement()! }
                let licenseType = PackageCollectionsModel.LicenseType.allCases.randomElement()!
                let license = PackageCollectionsModel.License(type: licenseType, url: URL(string: "http://\(licenseType).license")!)

                return PackageCollectionsModel.Package.Version(version: TSCUtility.Version(versionIndex, 0, 0),
                                                               packageName: "package-\(packageIndex)",
                                                               targets: targets,
                                                               products: products,
                                                               toolsVersion: .currentToolsVersion,
                                                               minimumPlatformVersions: minimumPlatformVersions,
                                                               verifiedPlatforms: verifiedPlatforms,
                                                               verifiedSwiftVersions: verifiedSwiftVersions,
                                                               license: license)
            }

            return PackageCollectionsModel.Package(repository: RepositorySpecifier(url: "https://package-\(packageIndex)"),
                                                   summary: "package \(packageIndex) description",
                                                   keywords: (0 ..< Int.random(in: 1 ... 3)).map { "keyword \($0)" },
                                                   versions: versions,
                                                   latestVersion: versions.first,
                                                   watchersCount: Int.random(in: 1 ... 1000),
                                                   readmeURL: URL(string: "https://package-\(packageIndex)-readme")!,
                                                   authors: nil)
        }

        return PackageCollectionsModel.Collection(source: .init(type: .json, url: URL(string: "https://feed-\(collectionIndex)")!),
                                                  name: "collection \(collectionIndex)",
                                                  overview: "collection \(collectionIndex) description",
                                                  keywords: (0 ..< Int.random(in: 1 ... 3)).map { "keyword \($0)" },
                                                  packages: packages,
                                                  createdAt: Date(),
                                                  createdBy: PackageCollectionsModel.Collection.Author(name: "Jane Doe"))
    }
}

func makeMockPackageBasicMetadata() -> PackageCollectionsModel.PackageBasicMetadata {
    return .init(summary: UUID().uuidString,
                 keywords: (0 ..< Int.random(in: 1 ... 3)).map { "keyword \($0)" },
                 versions: (0 ..< Int.random(in: 1 ... 10)).map { TSCUtility.Version($0, 0, 0) },
                 watchersCount: Int.random(in: 0 ... 50),
                 readmeURL: URL(string: "https://package-readme")!,
                 authors: (0 ..< Int.random(in: 1 ... 10)).map { .init(username: "\($0)", url: nil, service: nil) },
                 processedAt: Date())
}

func makeMockStorage() -> PackageCollections.Storage {
    let mockFileSystem = InMemoryFileSystem()
    return .init(sources: FilePackageCollectionsSourcesStorage(fileSystem: mockFileSystem),
                 collections: SQLitePackageCollectionsStorage(location: .memory))
}

struct MockCollectionsProvider: PackageCollectionProvider {
    let collections: [PackageCollectionsModel.Collection]

    init(_ collections: [PackageCollectionsModel.Collection]) {
        self.collections = collections
    }

    func get(_ source: PackageCollectionsModel.CollectionSource, callback: @escaping (Result<PackageCollectionsModel.Collection, Error>) -> Void) {
        if let collection = (self.collections.first { $0.source == source }) {
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
}
