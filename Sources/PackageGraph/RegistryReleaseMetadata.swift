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

import struct Foundation.URL
import struct TSCUtility.Version

public struct RegistryReleaseMetadata {
    /// Information from the signing certificate.
    public enum Certificate {
        case trusted(commonName: String, organization: String, identity: String?)
        case untrusted(commonName: String, organization: String)
        case none
    }

    /// Metadata of the given release, provided by the registry.
    public struct Metadata {
        public struct Author {
            public let name: String
            public let emailAddress: String?
            public let description: String?
            public let url: URL?
            public let organization: Organization
        }

        public struct Organization {
            public let name: String
            public let emailAddress: String?
            public let description: String?
            public let url: URL?
        }

        public let author: Author?
        public let description: String?
        public let licenseURL: URL?
        public let readmeURL: URL?
        public let scmRepositoryURLs: [URL]
        public let version: Version
    }

    /// Information about the source of the release.
    public enum Source {
        case registry(URL)
    }

    public let certificate: Certificate
    public let metadata: Metadata
    public let source: Source
}
