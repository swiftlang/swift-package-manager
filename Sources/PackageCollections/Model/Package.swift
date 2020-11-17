/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import struct Foundation.URL

import PackageModel
import SourceControl

extension PackageCollectionsModel {
    /// Package metadata
    public struct Package: Equatable {
        /// Package reference
        public let reference: PackageReference

        /// Package's repository address
        public let repository: RepositorySpecifier

        /// Package description
        public let description: String?

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
        public let latestVersion: Version?

        /// Number of watchers
        public let watchersCount: Int?

        /// URL of the package's README
        public let readmeURL: URL?

        /// Package authors
        public let authors: [Author]?

        /// Initializes a `PackageMetadata`
        init(
            repository: RepositorySpecifier,
            description: String?,
            versions: [Version],
            latestVersion: Version?,
            watchersCount: Int?,
            readmeURL: URL?,
            authors: [Author]?
        ) {
            self.reference = .init(repository: repository)
            self.repository = repository
            self.description = description
            self.versions = versions
            self.latestVersion = latestVersion
            self.watchersCount = watchersCount
            self.readmeURL = readmeURL
            self.authors = authors
        }
    }
}

// FIXME: add minimumPlatformVersions
extension PackageCollectionsModel.Package {
    /// A representation of package version
    public struct Version: Equatable {
        public typealias Target = PackageCollectionsModel.PackageTarget
        public typealias Product = PackageCollectionsModel.PackageProduct

        /// The version
        public let version: TSCUtility.Version

        /// The package name
        public let packageName: String

        // Custom instead of `PackageModel.Target` because we don't need the additional details
        /// The package version's targets
        public let targets: [Target]

        // Custom instead of `PackageModel.Product` because of the simplified `Target`
        /// The package version's products
        public let products: [Product]

        /// The package version's Swift tools version
        public let toolsVersion: ToolsVersion

        /// The package version's supported platforms verified to work
        public let verifiedPlatforms: [PackageModel.Platform]?

        /// The package version's Swift versions verified to work
        public let verifiedSwiftVersions: [SwiftLanguageVersion]?

        /// The package version's license
        public let license: PackageCollectionsModel.License?
    }
}

extension PackageCollectionsModel {
    /// A representation of package target
    public struct PackageTarget: Equatable, Hashable, Codable {
        /// The target name
        public let name: String

        /// Target module name
        public let moduleName: String?
    }
}

extension PackageCollectionsModel {
    /// A representation of package product
    public struct PackageProduct: Equatable, Codable {
        /// The product name
        public let name: String

        /// The product type
        public let type: ProductType

        /// The product's targets
        public let targets: [PackageTarget]
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
