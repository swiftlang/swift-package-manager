/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020-2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import struct Foundation.Date
import struct Foundation.URL

import PackageModel
import SourceControl

extension PackageCollectionsModel {
    /// Package metadata
    public struct Package: Codable, Equatable {
        /// Package reference
        public let reference: PackageReference

        /// Package's repository address
        public let repository: RepositorySpecifier

        /// Package description
        public let summary: String?

        /// Keywords for the package
        public let keywords: [String]?

        /// Published versions of the package
        public let versions: [Version]

        /// The latest published version of the package
        ///
        /// - Note:
        ///     This would be the latest released version, unless no release versions are published
        ///     in which case it will be the latest pre-release version.
        ///
        ///     E.g. given:
        ///     3.0.0-beta.1
        ///     2.1.1
        ///     2.1.0
        ///     2.0.0
        ///     2.0.0-beta.2
        ///     2.0.0-beta.1
        ///     1.0.1
        ///     1.0.0
        ///
        ///     Latest =  2.1.1
        ///
        ///     And given:
        ///     1.0.0-beta.3
        ///     1.0.0-beta.2
        ///     1.0.0-beta.1
        ///
        ///     Latest = 1.0.0-beta.3
        public var latestVersion: Version? {
            self.latestReleaseVersion ?? self.latestPrereleaseVersion
        }

        public var latestReleaseVersion: Version? {
            self.versions.latestRelease
        }

        public var latestPrereleaseVersion: Version? {
            self.versions.latestPrerelease
        }

        /// Number of watchers
        public let watchersCount: Int?

        /// URL of the package's README
        public let readmeURL: URL?

        /// The package's current license info
        public let license: License?

        /// Package authors
        public let authors: [Author]?

        /// The package's programming languages
        public let languages: Set<String>?

        /// Initializes a `Package`
        init(
            repository: RepositorySpecifier,
            summary: String?,
            keywords: [String]?,
            versions: [Version],
            watchersCount: Int?,
            readmeURL: URL?,
            license: License?,
            authors: [Author]?,
            languages: Set<String>?
        ) {
            self.reference = .init(repository: repository)
            self.repository = repository
            self.summary = summary
            self.keywords = keywords
            self.versions = versions
            self.watchersCount = watchersCount
            self.readmeURL = readmeURL
            self.license = license
            self.authors = authors
            self.languages = languages
        }
    }
}

extension PackageCollectionsModel.Package {
    /// A representation of package version
    public struct Version: Codable, Equatable {
        public typealias Target = PackageCollectionsModel.Target
        public typealias Product = PackageCollectionsModel.Product

        /// The version
        public let version: TSCUtility.Version

        /// The title or name of the version
        public let title: String?

        /// Package version description
        public let summary: String?

        // TODO: remove (replaced by manifests)
        public var packageName: String { self.defaultManifest!.packageName }

        // TODO: remove (replaced by manifests)
        public var targets: [Target] { self.defaultManifest!.targets }

        // TODO: remove (replaced by manifests)
        public var products: [Product] { self.defaultManifest!.products }

        // TODO: remove (replaced by manifests)
        public var toolsVersion: ToolsVersion { self.defaultManifest!.toolsVersion }

        // TODO: remove (replaced by manifests)
        public var minimumPlatformVersions: [SupportedPlatform]? { nil }

        /// Manifests by tools version
        public let manifests: [ToolsVersion: Manifest]

        /// Tools version of the default manifest
        public let defaultToolsVersion: ToolsVersion

        // TODO: remove (replaced by verifiedCompatibility)
        public var verifiedPlatforms: [PackageModel.Platform]? { nil }

        // TODO: remove (replaced by verifiedCompatibility)
        public var verifiedSwiftVersions: [SwiftLanguageVersion]? { nil }

        /// An array of compatible platforms and Swift versions that has been tested and verified for.
        public let verifiedCompatibility: [PackageCollectionsModel.Compatibility]?

        /// The package version's license
        public let license: PackageCollectionsModel.License?

        /// When the package version was created
        public let createdAt: Date?

        public struct Manifest: Equatable, Codable {
            /// The Swift tools version specified in `Package.swift`.
            public let toolsVersion: ToolsVersion

            /// The package name
            public let packageName: String

            // Custom instead of `PackageModel.Target` because we don't need the additional details
            /// The package version's targets
            public let targets: [Target]

            // Custom instead of `PackageModel.Product` because of the simplified `Target`
            /// The package version's products
            public let products: [Product]

            /// The package version's supported platforms
            public let minimumPlatformVersions: [SupportedPlatform]?
        }
    }
}

extension PackageCollectionsModel {
    /// A representation of package target
    public struct Target: Equatable, Hashable, Codable {
        /// The target name
        public let name: String

        /// Target module name
        public let moduleName: String?
    }
}

extension PackageCollectionsModel {
    /// A representation of package product
    public struct Product: Equatable, Codable {
        /// The product name
        public let name: String

        /// The product type
        public let type: ProductType

        /// The product's targets
        public let targets: [Target]
    }
}

extension PackageCollectionsModel {
    /// Compatible platform and Swift version.
    public struct Compatibility: Equatable, Codable {
        /// The platform (e.g., macOS, Linux, etc.)
        public let platform: PackageModel.Platform

        /// The Swift version
        public let swiftVersion: SwiftLanguageVersion
    }
}

extension PackageCollectionsModel.Package {
    /// A representation of package author
    public struct Author: Equatable, Codable {
        /// Author's username
        public let username: String

        /// Author's URL (e.g., profile)
        public let url: URL?

        /// Service that provides the user information
        public let service: Service?

        /// A representation of user service
        public struct Service: Equatable, Codable {
            /// The service name
            public let name: String
        }
    }
}

extension PackageCollectionsModel {
    public typealias PackageMetadata = (package: PackageCollectionsModel.Package, collections: [PackageCollectionsModel.CollectionIdentifier])
}

// MARK: - Utilities

extension PackageCollectionsModel.Package.Version: Comparable {
    public static func < (lhs: PackageCollectionsModel.Package.Version, rhs: PackageCollectionsModel.Package.Version) -> Bool {
        lhs.version < rhs.version
    }
}

extension Array where Element == PackageCollectionsModel.Package.Version {
    var latestRelease: PackageCollectionsModel.Package.Version? {
        self.filter { $0.version.prereleaseIdentifiers.isEmpty }
            .sorted(by: >)
            .first
    }

    var latestPrerelease: PackageCollectionsModel.Package.Version? {
        self.filter { !$0.version.prereleaseIdentifiers.isEmpty }
            .sorted(by: >)
            .first
    }
}

extension PackageCollectionsModel.Package.Version {
    public var defaultManifest: Manifest? {
        self.manifests[self.defaultToolsVersion]
    }
}
