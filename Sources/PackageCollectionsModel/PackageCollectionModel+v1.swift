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

import Foundation

extension PackageCollectionModel {
    /// Version 1 of the package collection format.
    public enum V1 {}
}

extension PackageCollectionModel.V1 {
    /// A `Codable` representation of a package collection JSON document.
    ///
    /// Encode a `Collection` to JSON to produce a package collection file,
    /// or decode one from a JSON document. For production distribution,
    /// wrap the collection in a ``SignedCollection``.
    public struct Collection: Equatable, Codable {
        /// The name of the package collection, for display purposes only.
        public let name: String

        /// A description of the package collection.
        public let overview: String?

        /// An array of keywords associated with the collection.
        public let keywords: [String]?

        /// An array of package metadata objects.
        public let packages: [PackageCollectionModel.V1.Collection.Package]

        /// The version of the format to which the collection conforms.
        ///
        /// Currently, the only supported value is ``PackageCollectionModel/FormatVersion/v1_0``.
        /// Passing any other value triggers a runtime precondition failure.
        public let formatVersion: PackageCollectionModel.FormatVersion

        /// The revision number of this package collection.
        public let revision: Int?

        /// The generation date for this package collection.
        public let generatedAt: Date

        /// The author of this package collection.
        public let generatedBy: Author?

        /// Creates a `Collection`.
        public init(
            name: String,
            overview: String?,
            keywords: [String]?,
            packages: [PackageCollectionModel.V1.Collection.Package],
            formatVersion: PackageCollectionModel.FormatVersion,
            revision: Int?,
            generatedAt: Date = Date(),
            generatedBy: Author?
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

        /// The entity that generated the collection, such as a person or organization.
        ///
        /// This type is distinct from ``PackageCollectionModel/V1/Collection/Package/Version/Author``,
        /// which represents the author of a specific package version.
        public struct Author: Equatable, Codable {
            /// The author name, which may be a person or organization.
            public let name: String

            /// Creates an `Author`.
            public init(name: String) {
                self.name = name
            }
        }
    }
}

extension PackageCollectionModel.V1.Collection {
    /// Metadata about a package included in a collection, including its URL,
    /// versions, and license information.
    public struct Package: Equatable, Codable {
        /// The URL of the package.
        ///
        /// By convention, this is a Git repository URL. The URL should use HTTPS
        /// and may contain a `.git` suffix.
        public let url: URL

        /// An optional package identity that overrides the identity derived from the URL.
        ///
        /// When `nil`, consumers should derive the identity from ``url``.
        /// Set this when the package is published to a registry or when the
        /// URL-derived identity is not appropriate.
        public let identity: String?

        /// A description of the package.
        public let summary: String?

        /// An array of keywords associated with the package.
        public let keywords: [String]?

        /// An array of version objects representing the most recent and/or relevant releases of the package.
        public let versions: [PackageCollectionModel.V1.Collection.Package.Version]

        /// The URL of the package's README.
        public let readmeURL: URL?

        /// The package's current license information.
        public let license: PackageCollectionModel.V1.License?

        /// Creates a `Package`.
        public init(
            url: URL,
            identity: String? = nil,
            summary: String?,
            keywords: [String]?,
            versions: [PackageCollectionModel.V1.Collection.Package.Version],
            readmeURL: URL?,
            license: PackageCollectionModel.V1.License?
        ) {
            self.url = url
            self.identity = identity
            self.summary = summary
            self.keywords = keywords
            self.versions = versions
            self.readmeURL = readmeURL
            self.license = license
        }
    }
}

extension PackageCollectionModel.V1.Collection.Package {
    /// A specific release of a package, containing one or more manifests keyed by
    /// Swift tools version along with compatibility and signing information.
    public struct Version: Equatable, Codable {
        /// The semantic version string.
        public let version: String

        /// A description of the package version.
        public let summary: String?

        /// Manifests keyed by tools version string.
        ///
        /// Each key must match the ``Manifest/toolsVersion`` of its corresponding value.
        public let manifests: [String: Manifest]

        /// The tools version of the default manifest.
        ///
        /// This value must exist as a key in ``manifests``.
        public let defaultToolsVersion: String

        /// An array of platforms and Swift versions with verified compatibility.
        public let verifiedCompatibility: [PackageCollectionModel.V1.Compatibility]?

        /// The package version's license.
        public let license: PackageCollectionModel.V1.License?

        /// The author of the package version.
        public let author: Author?

        /// The signer of the package version.
        public let signer: PackageCollectionModel.V1.Signer?

        /// The creation date for this package version.
        public let createdAt: Date?

        /// Creates a `Version`.
        public init(
            version: String,
            summary: String?,
            manifests: [String: Manifest],
            defaultToolsVersion: String,
            verifiedCompatibility: [PackageCollectionModel.V1.Compatibility]?,
            license: PackageCollectionModel.V1.License?,
            author: Author?,
            signer: PackageCollectionModel.V1.Signer?,
            createdAt: Date?
        ) {
            self.version = version
            self.summary = summary
            self.manifests = manifests
            self.defaultToolsVersion = defaultToolsVersion
            self.verifiedCompatibility = verifiedCompatibility
            self.license = license
            self.author = author
            self.signer = signer
            self.createdAt = createdAt
        }

        /// The resolved manifest data for a specific Swift tools version, including the
        /// package name, targets, products, and minimum platform versions.
        public struct Manifest: Equatable, Codable {
            /// The Swift tools version specified in `Package.swift` (for example, `5.7` or `5.9.2`).
            public let toolsVersion: String

            /// The name of the package.
            public let packageName: String

            /// An array of the package version's targets.
            public let targets: [PackageCollectionModel.V1.Target]

            /// An array of the package version's products.
            public let products: [PackageCollectionModel.V1.Product]

            /// An array of the package version’s supported platforms specified in `Package.swift`.
            public let minimumPlatformVersions: [PackageCollectionModel.V1.PlatformVersion]?

            /// Creates a `Manifest`.
            public init(
                toolsVersion: String,
                packageName: String,
                targets: [PackageCollectionModel.V1.Target],
                products: [PackageCollectionModel.V1.Product],
                minimumPlatformVersions: [PackageCollectionModel.V1.PlatformVersion]?
            ) {
                self.toolsVersion = toolsVersion
                self.packageName = packageName
                self.targets = targets
                self.products = products
                self.minimumPlatformVersions = minimumPlatformVersions
            }
        }

        /// The author of a package version.
        ///
        /// This type is distinct from ``PackageCollectionModel/V1/Collection/Author``,
        /// which represents the author of the collection itself.
        public struct Author: Equatable, Codable {
            /// The author name.
            public let name: String

            /// Creates an `Author`.
            public init(name: String) {
                self.name = name
            }
        }
    }
}

extension PackageCollectionModel.V1 {
    /// A target within a package, with an optional module name for importable targets.
    public struct Target: Equatable, Codable {
        /// The target name.
        public let name: String

        /// The module name if you can import this target as a module; `nil` otherwise.
        public let moduleName: String?

        /// Creates a `Target`.
        public init(name: String, moduleName: String?) {
            self.name = name
            self.moduleName = moduleName
        }
    }

    /// A product in a package.
    public struct Product: Equatable, Codable {
        /// The product name.
        public let name: String

        /// The product type.
        public let type: ProductType

        /// An array of the product’s targets.
        public let targets: [String]

        /// Creates a `Product`.
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

    /// A platform name paired with its minimum deployment target version string
    /// (for example, macOS `10.15` or iOS `13.0`).
    public struct PlatformVersion: Equatable, Codable {
        /// The name of the platform (such as macOS and Linux).
        public let name: String

        /// The minimum deployment target version string for the platform (for example, `10.15` or `13.0`).
        public let version: String

        /// Creates a `PlatformVersion`.
        public init(name: String, version: String) {
            self.name = name
            self.version = version
        }
    }

    /// A platform identified by name, used within ``Compatibility``
    /// to pair with a Swift version.
    public struct Platform: Equatable, Codable {
        /// The name of the platform (such as macOS and Linux).
        public let name: String

        /// Creates a `Platform`.
        public init(name: String) {
            self.name = name
        }
    }

    /// A verified platform and Swift version combination, indicating that the
    /// package was successfully built and tested with this configuration.
    public struct Compatibility: Equatable, Codable {
        /// The platform (such as macOS and Linux).
        public let platform: Platform

        /// The Swift version.
        public let swiftVersion: String

        /// Creates a `Compatibility`.
        public init(platform: Platform, swiftVersion: String) {
            self.platform = platform
            self.swiftVersion = swiftVersion
        }
    }

    /// License information for a package or package version, pairing a license
    /// name with the URL of the license file.
    ///
    /// Use an SPDX identifier for the name when possible.
    public struct License: Equatable, Codable {
        /// The license name, preferably an SPDX identifier (such as `Apache-2.0` or `MIT`).
        public let name: String?

        /// The URL of the license file.
        public let url: URL

        /// Creates a `License`.
        public init(name: String?, url: URL) {
            self.name = name
            self.url = url
        }
    }

    /// The entity that signed a package version, identified by certificate subject fields.
    ///
    /// Currently the only valid signer type is `ADP` (Apple Developer Program).
    public struct Signer: Equatable, Codable {
        /// The signer type. Currently the only valid value is `ADP` (Apple Developer Program).
        public let type: String

        /// The common name of the signing certificate's subject.
        public let commonName: String

        /// The organizational unit name of the signing certificate's subject.
        public let organizationalUnitName: String

        /// The organization name of the signing certificate's subject.
        public let organizationName: String

        /// Creates a `Signer`.
        public init(
            type: String,
            commonName: String,
            organizationalUnitName: String,
            organizationName: String
        ) {
            self.type = type
            self.commonName = commonName
            self.organizationalUnitName = organizationalUnitName
            self.organizationName = organizationName
        }
    }
}

extension PackageCollectionModel.V1.Platform: Hashable {
    public var hashValue: Int { name.hashValue }

    public func hash(into hasher: inout Hasher) {
        name.hash(into: &hasher)
    }
}

extension PackageCollectionModel.V1.Platform: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.name < rhs.name
    }
}

extension PackageCollectionModel.V1.Compatibility: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.platform != rhs.platform { return lhs.platform < rhs.platform }
        return lhs.swiftVersion < rhs.swiftVersion
    }
}

// MARK: -  Copy `PackageModel.ProductType` to minimize the module's dependencies

extension PackageCollectionModel.V1 {
    /// The type of product.
    public enum ProductType: Equatable {
        /// The type of library.
        public enum LibraryType: String, Codable {
            /// Static library.
            case `static`

            /// Dynamic library.
            case dynamic

            /// The package manager determines the library type.
            case automatic
        }

        /// A library product.
        case library(LibraryType)

        /// An executable product.
        case executable

        /// A plugin product.
        case plugin

        /// An executable code snippet.
        case snippet

        /// A test product.
        case test

        /// A macro product.
        case `macro`
    }
}

extension PackageCollectionModel.V1.ProductType: Codable {
    private enum CodingKeys: String, CodingKey {
        case library, executable, plugin, snippet, test, `macro`
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .library(let a1):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .library)
            try unkeyedContainer.encode(a1)
        case .executable:
            try container.encodeNil(forKey: .executable)
        case .plugin:
            try container.encodeNil(forKey: .plugin)
        case .snippet:
            try container.encodeNil(forKey: .snippet)
        case .test:
            try container.encodeNil(forKey: .test)
        case .macro:
            try container.encodeNil(forKey: .macro)
        }
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard let key = values.allKeys.first(where: values.contains) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Did not find a matching key"))
        }
        switch key {
        case .library:
            var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
            let a1 = try unkeyedValues.decode(PackageCollectionModel.V1.ProductType.LibraryType.self)
            self = .library(a1)
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

// MARK: - Signed package collection

extension PackageCollectionModel.V1 {
    /// A package collection paired with a cryptographic signature for verification.
    ///
    /// When encoded to JSON, `SignedCollection` produces a flat structure identical
    /// to ``Collection`` with an additional top-level `signature` key, rather than
    /// nesting the collection under a separate key.
    public struct SignedCollection: Equatable {
        /// The package collection.
        public let collection: PackageCollectionModel.V1.Collection

        /// The signature and metadata.
        public let signature: PackageCollectionModel.V1.Signature

        /// Creates a `SignedCollection`.
        public init(collection: PackageCollectionModel.V1.Collection, signature: PackageCollectionModel.V1.Signature) {
            self.collection = collection
            self.signature = signature
        }
    }

    /// A cryptographic signature and the certificate metadata used to verify a
    /// package collection.
    public struct Signature: Equatable, Codable {
        /// The signature.
        public let signature: String

        /// Details about the certificate that generated the signature.
        public let certificate: Certificate

        /// Creates a `Signature`.
        public init(signature: String, certificate: Certificate) {
            self.signature = signature
            self.certificate = certificate
        }

        /// The X.509 certificate that signs a package collection, represented by its
        /// subject and issuer distinguished names.
        public struct Certificate: Equatable, Codable {
            /// The subject of the certificate.
            public let subject: Name

            /// The issuer of the certificate.
            public let issuer: Name

            /// Creates a `Certificate`.
            public init(subject: Name, issuer: Name) {
                self.subject = subject
                self.issuer = issuer
            }

            /// The distinguished name fields of a certificate, used to represent
            /// both the subject and the issuer.
            public struct Name: Equatable, Codable {
                /// The user ID.
                public let userID: String?

                /// The common name.
                public let commonName: String?

                /// The organizational unit.
                public let organizationalUnit: String?

                /// The organization.
                public let organization: String?

                /// Creates a `Name`.
                public init(
                    userID: String?,
                    commonName: String?,
                    organizationalUnit: String?,
                    organization: String?
                ) {
                    self.userID = userID
                    self.commonName = commonName
                    self.organizationalUnit = organizationalUnit
                    self.organization = organization
                }
            }
        }
    }
}

extension PackageCollectionModel.V1.SignedCollection: Codable {
    enum CodingKeys: String, CodingKey {
        // Collection properties
        case name
        case overview
        case keywords
        case packages
        case formatVersion
        case revision
        case generatedAt
        case generatedBy

        case signature
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.collection.name, forKey: .name)
        try container.encodeIfPresent(self.collection.overview, forKey: .overview)
        try container.encodeIfPresent(self.collection.keywords, forKey: .keywords)
        try container.encode(self.collection.packages, forKey: .packages)
        try container.encode(self.collection.formatVersion, forKey: .formatVersion)
        try container.encodeIfPresent(self.collection.revision, forKey: .revision)
        try container.encode(self.collection.generatedAt, forKey: .generatedAt)
        try container.encodeIfPresent(self.collection.generatedBy, forKey: .generatedBy)
        try container.encode(self.signature, forKey: .signature)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.collection = try PackageCollectionModel.V1.Collection(from: decoder)
        self.signature = try container.decode(PackageCollectionModel.V1.Signature.self, forKey: .signature)
    }
}
