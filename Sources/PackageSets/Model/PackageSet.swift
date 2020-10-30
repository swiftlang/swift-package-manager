/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import struct Foundation.Date
import struct Foundation.URL

import PackageModel
import SourceControl
import TSCUtility

public enum PackageSetsModel {}

extension PackageSetsModel {
    /// A `PackageSet` is a grouping of package metadata.
    public struct PackageSet {
        public typealias Identifier = PackageSetIdentifier
        public typealias Source = PackageSetSource

        /// The identifier of the group
        public let identifier: Identifier

        /// Where the group and its contents are obtained
        public let source: Source

        /// The name of the group
        public let name: String

        /// The description of the group
        public let description: String?

        /// Keywords for the group
        public let keywords: [String]?

        /// Metadata of packages belonging to the group
        public let packages: [Package]

        /// When this group was created/published by the source
        public let createdAt: Date

        /// When this group was last processed locally
        public let lastProcessedAt: Date

        /// Initializes a `PackageSet`
        init(
            source: Source,
            name: String,
            description: String?,
            keywords: [String]?,
            packages: [Package],
            createdAt: Date,
            lastProcessedAt: Date = Date()
        ) {
            self.identifier = .init(source: source)
            self.source = source
            self.name = name
            self.description = description
            self.keywords = keywords
            self.packages = packages
            self.createdAt = createdAt
            self.lastProcessedAt = lastProcessedAt
        }
    }
}

extension PackageSetsModel {
    /// Represents the source of a `PackageSet`
    public enum PackageSetSource {
        /// Package feed at URL
        case feed(URL)
    }
}

extension PackageSetsModel {
    /// Represents the identifier of a `PackageSet`
    public enum PackageSetIdentifier: Hashable, Comparable {
        /// Package feed at URL
        case feed(URL)

        /// Creates an `Identifier` from `Source`
        init(source: PackageSetSource) {
            switch source {
            case .feed(let url):
                self = .feed(url)
            }
        }

        public static func < (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.feed(let lhs), .feed(let rhs)):
                return lhs.absoluteString < rhs.absoluteString
            }
        }
    }
}

extension PackageSetsModel.PackageSet {
    /// A representation of package metadata
    public struct Package {
        public typealias Version = PackageVersion

        /// Package reference
        public let reference: PackageReference

        /// Package's repository address
        public let repository: RepositorySpecifier

        /// A summary about the package
        public let summary: String?

        /// Published versions of the package
        public let versions: [Version]

        /// URL of the package's README
        public let readmeURL: URL?

        /// Initializes a `Package`
        init(
            repository: RepositorySpecifier,
            summary: String?,
            versions: [Version],
            readmeURL: URL?
        ) {
            self.reference = .init(repository: repository)
            self.repository = repository
            self.summary = summary
            self.versions = versions
            self.readmeURL = readmeURL
        }
    }
}

extension PackageSetsModel.PackageSet {
    /// A representation of package version
    public struct PackageVersion {
        public typealias Target = PackageTarget
        public typealias Product = PackageProduct

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
        public let swiftToolsVersion: ToolsVersion
        
        /// The package version's supported platforms
        public let supportedPlatforms: [PackageModel.Platform]?

        /// The package version's  Swift versions confirmed to work
        public let confirmedSwiftVersions: [SwiftLanguageVersion]?

        /// The package version's license
        public let license: PackageSetsModel.License?
    }
}

extension PackageSetsModel.PackageSet {
    /// Represents a package target
    public struct PackageTarget {
        /// Target name
        public let name: String
        /// Target module name
        public let moduleName: String?
    }
}

extension PackageSetsModel.PackageSet {
    /// Represents a package product
    public struct PackageProduct {
        /// Product name
        let name: String

        /// Product type
        let type: ProductType

        /// The product's targets
        let targets: [Target]
    }
}
