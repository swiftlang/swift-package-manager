//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct Basics.SourceControlURL
import struct Foundation.URL
import struct TSCUtility.Version


public struct RegistryReleaseMetadata: Hashable {
    public let source: Source
    public let metadata: Metadata
    public let signature: RegistrySignature?

    public init(
        source: RegistryReleaseMetadata.Source,
        metadata: RegistryReleaseMetadata.Metadata,
        signature: RegistrySignature?
    ) {
        self.source = source
        self.metadata = metadata
        self.signature = signature
    }

    /// Metadata of the given release, provided by the registry.
    public struct Metadata: Hashable {
        public let author: Author?
        public let description: String?
        public let licenseURL: URL?
        public let readmeURL: URL?
        public let scmRepositoryURLs: [SourceControlURL]?

        public init(
            author: RegistryReleaseMetadata.Metadata.Author? = nil,
            description: String? = nil,
            licenseURL: URL? = nil,
            readmeURL: URL? = nil,
            scmRepositoryURLs: [SourceControlURL]?
        ) {
            self.author = author
            self.description = description
            self.licenseURL = licenseURL
            self.readmeURL = readmeURL
            self.scmRepositoryURLs = scmRepositoryURLs
        }

        public struct Author: Hashable {
            public let name: String
            public let emailAddress: String?
            public let description: String?
            public let url: URL?
            public let organization: Organization?

            public init(
                name: String,
                emailAddress: String? = nil,
                description: String? = nil,
                url: URL? = nil,
                organization: RegistryReleaseMetadata.Metadata.Organization?
            ) {
                self.name = name
                self.emailAddress = emailAddress
                self.description = description
                self.url = url
                self.organization = organization
            }
        }

        public struct Organization: Hashable {
            public let name: String
            public let emailAddress: String?
            public let description: String?
            public let url: URL?

            public init(name: String, emailAddress: String? = nil, description: String? = nil, url: URL? = nil) {
                self.name = name
                self.emailAddress = emailAddress
                self.description = description
                self.url = url
            }
        }
    }

    /// Information from the signing certificate.
    public struct RegistrySignature: Hashable, Codable {
        public let signedBy: SigningEntity?
        public let format: String
        public let value: [UInt8]

        public init(
            signedBy: SigningEntity?,
            format: String,
            value: [UInt8]
        ) {
            self.signedBy = signedBy
            self.format = format
            self.value = value
        }
    }

    public enum SigningEntity: Codable, Hashable, Sendable {
        case recognized(type: String, commonName: String?, organization: String?, identity: String?)
        case unrecognized(commonName: String?, organization: String?)
    }
    
    /// Information about the source of the release.
    public enum Source: Hashable {
        case registry(URL)
    }
}
