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

extension PackageSetsModel {
    /// Package metadata
    public struct Package {
        /// Package reference
        public let reference: PackageReference

        /// Package's repository address
        public let repository: RepositorySpecifier

        /// Package description
        public let description: String?

        /// Published versions of the package
        public let versions: [Version]

        /// The latest published version of the package
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

extension PackageSetsModel.Package {
    /// A representation of package version
    public struct Version {
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

        /// The package version's supported Swift versions
        public let confirmedSwiftVersions: [SwiftLanguageVersion]?

        /// The package version's CVEs
        public let cves: [PackageSetsModel.CVE]?

        /// The package version's license
        public let license: PackageSetsModel.License?
    }
}

extension PackageSetsModel.Package {
    /// A representation of package target
    public struct Target {
        /// The target name
        public let name: String
    }
}

extension PackageSetsModel.Package {
    /// A representation of package product
    public struct Product {
        /// The product name
        public let name: String

        /// The product type
        public let type: ProductType

        /// The product's targets
        public let targets: [Target]
    }
}

extension PackageSetsModel.Package {
    /// A representation of package author
    public struct Author {
        /// Author's username
        public let username: String

        /// Author's URL (e.g., profile)
        public let url: URL?

        /// Service that provides the user information
        public let service: Service?

        /// A representation of user service
        public struct Service {
            /// The service name
            public let name: String
        }
    }
}
