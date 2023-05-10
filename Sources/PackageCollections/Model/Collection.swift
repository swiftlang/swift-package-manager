//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020-2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import struct Foundation.Date
import struct Foundation.URL
import PackageModel
import SourceControl

public enum PackageCollectionsModel {}

// make things less verbose internally
internal typealias Model = PackageCollectionsModel

extension PackageCollectionsModel {
    /// A `Collection` is a collection of packages.
    public struct Collection: Equatable, Codable {
        public typealias Identifier = CollectionIdentifier
        public typealias Source = CollectionSource

        /// The identifier of the collection
        public let identifier: Identifier

        /// Where the collection and its contents are obtained
        public internal(set) var source: Source

        /// The name of the collection
        public let name: String

        /// The description of the collection
        public let overview: String?

        /// Keywords for the collection
        public let keywords: [String]?

        /// Metadata of packages belonging to the collection
        public let packages: [Package]

        /// When this collection was created/published by the source
        public let createdAt: Date

        /// Who authored this collection
        public let createdBy: Author?

        /// When this collection was last processed locally
        public let lastProcessedAt: Date

        /// The collection's signature metadata
        public let signature: SignatureData?

        /// Indicates if the collection is signed
        public var isSigned: Bool {
            self.signature != nil
        }

        /// Initializes a `Collection`
        init(
            source: Source,
            name: String,
            overview: String?,
            keywords: [String]?,
            packages: [Package],
            createdAt: Date,
            createdBy: Author?,
            signature: SignatureData?,
            lastProcessedAt: Date = Date()
        ) {
            self.identifier = .init(from: source)
            self.source = source
            self.name = name
            self.overview = overview
            self.keywords = keywords
            self.packages = packages
            self.createdAt = createdAt
            self.createdBy = createdBy
            self.signature = signature
            self.lastProcessedAt = lastProcessedAt
        }
    }
}

extension PackageCollectionsModel {
    /// Represents the source of a `Collection`
    public struct CollectionSource: Equatable, Hashable, Codable {
        /// Source type
        public let type: CollectionSourceType

        /// URL of the source file
        public let url: URL

        /// Indicates if the source is explicitly trusted or untrusted by the user
        public var isTrusted: Bool?

        /// Indicates if the source can skip signature validation
        public var skipSignatureCheck: Bool

        /// The source's absolute file system path, if its URL is of 'file' scheme.
        let absolutePath: AbsolutePath?

        public init(type: CollectionSourceType, url: URL, isTrusted: Bool? = nil, skipSignatureCheck: Bool = false) {
            self.type = type
            self.url = url
            self.isTrusted = isTrusted
            self.skipSignatureCheck = skipSignatureCheck

            if url.scheme?.lowercased() == "file", let absolutePath = try? AbsolutePath(validating: url.path) {
                self.absolutePath = absolutePath
            } else {
                self.absolutePath = nil
            }
        }

        public static func == (lhs: CollectionSource, rhs: CollectionSource) -> Bool {
            lhs.type == rhs.type && lhs.url == rhs.url
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(self.type)
            hasher.combine(self.url)
        }
    }

    /// Represents the source type of a `Collection`
    public enum CollectionSourceType: String, Codable, CaseIterable {
        case json
    }
}

extension PackageCollectionsModel {
    /// Represents the identifier of a `Collection`
    public enum CollectionIdentifier: Hashable, Comparable {
        /// JSON based package collection at URL
        case json(URL)

        /// Creates an `Identifier` from `Source`
        init(from source: CollectionSource) {
            switch source.type {
            case .json:
                self = .json(source.url)
            }
        }

        public static func < (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.json(let lhs), .json(let rhs)):
                return lhs.absoluteString < rhs.absoluteString
            }
        }
    }
}

extension PackageCollectionsModel.CollectionIdentifier: Codable {
    public enum DiscriminatorKeys: String, Codable {
        case json
    }

    public enum CodingKeys: CodingKey {
        case _case
        case url
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(DiscriminatorKeys.self, forKey: ._case) {
        case .json:
            let url = try container.decode(URL.self, forKey: .url)
            self = .json(url)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .json(let url):
            try container.encode(DiscriminatorKeys.json, forKey: ._case)
            try container.encode(url, forKey: .url)
        }
    }
}

extension PackageCollectionsModel.Collection {
    /// Represents the author of a `Collection`
    public struct Author: Equatable, Codable {
        /// The name of the author
        public let name: String
    }
}

extension PackageCollectionsModel {
    /// Package collection signature metadata
    public struct SignatureData: Equatable, Codable {
        /// Details about the certificate used to generate the signature
        public let certificate: Certificate

        /// Indicates if the signature has been validated. This is set to false if signature check didn't take place.
        public let isVerified: Bool

        public init(certificate: Certificate, isVerified: Bool) {
            self.certificate = certificate
            self.isVerified = isVerified
        }

        public struct Certificate: Equatable, Codable {
            /// Subject of the certificate
            public let subject: Name

            /// Issuer of the certificate
            public let issuer: Name

            /// Creates a `Certificate`
            public init(subject: Name, issuer: Name) {
                self.subject = subject
                self.issuer = issuer
            }

            /// Generic certificate name (e.g., subject, issuer)
            public struct Name: Equatable, Codable {
                /// User ID
                public let userID: String?

                /// Common name
                public let commonName: String?

                /// Organizational unit
                public let organizationalUnit: String?

                /// Organization
                public let organization: String?

                /// Creates a `Name`
                public init(userID: String?,
                            commonName: String?,
                            organizationalUnit: String?,
                            organization: String?) {
                    self.userID = userID
                    self.commonName = commonName
                    self.organizationalUnit = organizationalUnit
                    self.organization = organization
                }
            }
        }
    }
}
