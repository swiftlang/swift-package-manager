/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import struct Foundation.Date
import struct Foundation.URL
import TSCUtility

import PackageModel

extension JSONPackageCollectionModel {
    public enum V1 {}
}

extension JSONPackageCollectionModel.V1 {
    public struct Collection: Equatable, Codable {
        /// The name of the package collection, for display purposes only.
        public let name: String

        /// A description of the package collection.
        public let overview: String?

        /// An array of keywords that the collection is associated with.
        public let keywords: [String]?

        /// An array of package metadata objects
        public let packages: [JSONPackageCollectionModel.V1.Collection.Package]

        /// The version of the format to which the collection conforms.
        public let formatVersion: JSONPackageCollectionModel.FormatVersion

        /// The revision number of this package collection.
        public let revision: Int?

        /// The ISO 8601-formatted datetime string when the package collection was generated.
        public let generatedAt: Date

        /// The author of this package collection.
        public let generatedBy: Author?

        /// Creates a `Collection`
        public init(
            name: String,
            overview: String? = nil,
            keywords: [String]? = nil,
            packages: [JSONPackageCollectionModel.V1.Collection.Package],
            formatVersion: JSONPackageCollectionModel.FormatVersion,
            revision: Int? = nil,
            generatedAt: Date = Date(),
            generatedBy: Author? = nil
        ) {
            precondition(formatVersion == .v1_0, "Unsupported format version: \(formatVersion)")

            self.name = name
            self.overview = overview
            self.keywords = keywords
            self.packages = packages
            self.formatVersion = formatVersion
            self.revision = revision
            self.generatedAt = generatedAt
            self.generatedBy = generatedBy
        }

        public struct Author: Equatable, Codable {
            /// The author name.
            public let name: String

            /// Creates an `Author`
            public init(name: String) {
                self.name = name
            }
        }
    }
}

extension JSONPackageCollectionModel.V1.Collection {
    public struct Package: Equatable, Codable {
        /// The URL of the package. Currently only Git repository URLs are supported.
        public let url: Foundation.URL

        /// A description of the package.
        public let summary: String?

        /// An array of keywords that the package is associated with.
        public let keywords: [String]?

        /// An array of version objects representing the most recent and/or relevant releases of the package.
        public let versions: [JSONPackageCollectionModel.V1.Collection.Package.Version]

        /// The URL of the package's README.
        public let readmeURL: Foundation.URL?

        /// Creates a `Package`
        public init(
            url: URL,
            summary: String? = nil,
            keywords: [String]? = nil,
            versions: [JSONPackageCollectionModel.V1.Collection.Package.Version],
            readmeURL: URL? = nil
        ) {
            self.url = url
            self.summary = summary
            self.keywords = keywords
            self.versions = versions
            self.readmeURL = readmeURL
        }
    }
}

extension JSONPackageCollectionModel.V1.Collection.Package {
    public struct Version: Equatable, Codable {
        /// The semantic version string.
        public let version: String

        /// The name of the package.
        public let packageName: String

        /// An array of the package version's targets.
        public let targets: [JSONPackageCollectionModel.V1.Target]

        /// An array of the package version's products.
        public let products: [JSONPackageCollectionModel.V1.Product]

        /// The tools (semantic) version specified in `Package.swift`.
        public let toolsVersion: String

        /// An array of the package version’s supported platforms specified in `Package.swift`.
        public let minimumPlatformVersions: [JSONPackageCollectionModel.V1.PlatformVersion]?

        /// An array of platforms in which the package version has been tested and verified.
        public let verifiedPlatforms: [JSONPackageCollectionModel.V1.Platform]?

        /// An array of Swift versions that the package version has been tested and verified for.
        public let verifiedSwiftVersions: [String]?

        /// The package version's license.
        public let license: JSONPackageCollectionModel.V1.License?

        /// Creates a `Version`
        public init(
            version: String,
            packageName: String,
            targets: [JSONPackageCollectionModel.V1.Target],
            products: [JSONPackageCollectionModel.V1.Product],
            toolsVersion: String,
            minimumPlatformVersions: [JSONPackageCollectionModel.V1.PlatformVersion]? = nil,
            verifiedPlatforms: [JSONPackageCollectionModel.V1.Platform]? = nil,
            verifiedSwiftVersions: [String]? = nil,
            license: JSONPackageCollectionModel.V1.License? = nil
        ) {
            self.version = version
            self.packageName = packageName
            self.targets = targets
            self.products = products
            self.toolsVersion = toolsVersion
            self.minimumPlatformVersions = minimumPlatformVersions
            self.verifiedPlatforms = verifiedPlatforms
            self.verifiedSwiftVersions = verifiedSwiftVersions
            self.license = license
        }
    }
}

extension JSONPackageCollectionModel.V1 {
    public struct Target: Equatable, Codable {
        /// The target name.
        public let name: String

        /// The module name if this target can be imported as a module.
        public let moduleName: String?

        /// Creates a `Target`
        public init(name: String, moduleName: String? = nil) {
            self.name = name
            self.moduleName = moduleName
        }
    }

    public struct Product: Equatable, Codable {
        /// The product name.
        public let name: String

        /// The product type.
        public let type: ProductType

        /// An array of the product’s targets.
        public let targets: [String]

        /// Creates a `Product`
        public init(
            name: String,
            type: ProductType,
            targets: [String]
        ) {
            self.name = name
            self.type = type
            self.targets = targets
        }
    }

    public struct PlatformVersion: Equatable, Codable {
        /// The name of the platform (e.g., macOS, Linux, etc.).
        public let name: String

        /// The semantic version of the platform.
        public let version: String

        /// Creates a `PlatformVersion`
        public init(name: String, version: String) {
            self.name = name
            self.version = version
        }
    }

    public struct Platform: Equatable, Codable {
        /// The name of the platform (e.g., macOS, Linux, etc.).
        public let name: String

        /// Creates a `Platform`
        public init(name: String) {
            self.name = name
        }
    }

    public struct License: Equatable, Codable {
        /// License name (e.g., Apache-2.0, MIT, etc.)
        public let name: String

        /// The URL of the license file.
        public let url: URL

        /// Creates a `License`
        public init(name: String, url: URL) {
            self.name = name
            self.url = url
        }
    }
}

// MARK: - Validations

extension JSONPackageCollectionModel.V1 {
    public struct Validator {
        public let configuration: Configuration
        
        public init(configuration: Configuration = .init()) {
            self.configuration = configuration
        }
        
        public func validate(collection: Collection) -> [ValidationMessage]? {
            var messages = [ValidationMessage]()
            
            let packages = collection.packages
            // Stop validating if collection doesn't pass basic checks
            if packages.isEmpty {
                messages.append(.error("A collection must contain at least one package.", property: "packages"))
            } else if packages.count > self.configuration.maximumPackageCount {
                messages.append(.warning("The collection has (\(packages.count)) packages, which is more than the recommended maximum (\(self.configuration.maximumPackageCount)) and extra data might be ignored.", property: "packages"))
            } else {
                packages.forEach { self.validate(package: $0, messages: &messages) }
            }
            
            guard messages.isEmpty else {
                return messages
            }
            
            return nil
        }
        
        // TODO: validate package url?
        private func validate(package: Collection.Package, messages: inout [ValidationMessage]) {
            let packageID = PackageIdentity(url: package.url.absoluteString).description
            
            // Check for duplicate versions
            let nonUniqueVersions = Dictionary(grouping: package.versions, by: { $0.version }).filter { $1.count > 1 }.keys
            if !nonUniqueVersions.isEmpty {
                messages.append(.error("Duplicate version(s) found in package \(packageID): \(nonUniqueVersions).", property: "package.versions"))
            }
            
            var nonSemanticVersions = [String]()
            let semanticVersions: [TSCUtility.Version] = package.versions.compactMap {
                let semver = TSCUtility.Version(string: $0.version)
                if semver == nil {
                    nonSemanticVersions.append($0.version)
                }
                return semver
            }
            
            guard nonSemanticVersions.isEmpty else {
                messages.append(.error("Non semantic version(s) found in package \(packageID): \(nonSemanticVersions).", property: "package.versions"))
                // The next part of validation requires sorting the semvers. Cannot continue if non-semver.
                return
            }
            
            let sortedVersions = semanticVersions.sorted(by: >)
            
            var currentMajor: Int?
            var majorCount = 0
            var minorCount = 0
            for version in sortedVersions {
                if version.major != currentMajor {
                    currentMajor = version.major
                    majorCount += 1
                    minorCount = 0
                }

                guard majorCount <= self.configuration.maximumMajorVersionCount else {
                    messages.append(.warning("Package \(packageID) includes too many major versions. Only \(self.configuration.maximumMajorVersionCount) is allowed and extra data might be ignored.", property: "package.versions"))
                    break
                }
                guard minorCount < self.configuration.maximumMinorVersionCount else {
                    // !-safe currentMajor cannot be nil at this point
                    messages.append(.warning("Package \(packageID) includes too many minor versions for major version \(currentMajor!). Only \(self.configuration.maximumMinorVersionCount) is allowed and extra data might be ignored.", property: "package.versions"))
                    break
                }

                minorCount += 1
            }
            
            package.versions.forEach { version in
                if version.products.isEmpty {
                    messages.append(.error("Package \(packageID) version \(version.version) does not contain any products.", property: "version.products"))
                }
                version.products.forEach { product in
                    if product.targets.isEmpty {
                        messages.append(.error("Product \(product.name) of package \(packageID) version \(version.version) does not contain any targets.", property: "product.targets"))
                    }
                }
                
                if version.targets.isEmpty {
                    messages.append(.error("Package \(packageID) version \(version.version) does not contain any targets.", property: "version.targets"))
                }
            }
        }
        
        public struct Configuration {
            public var maximumPackageCount: Int
            public var maximumMajorVersionCount: Int
            public var maximumMinorVersionCount: Int

            public init(maximumPackageCount: Int? = nil,
                        maximumMajorVersionCount: Int? = nil,
                        maximumMinorVersionCount: Int? = nil) {
                // TODO: where should we read defaults from?
                self.maximumPackageCount = maximumPackageCount ?? 50
                self.maximumMajorVersionCount = maximumMajorVersionCount ?? 2
                self.maximumMinorVersionCount = maximumMinorVersionCount ?? 3
            }
        }
    }
}
