//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

/// Package release metadata as defined by Appendix B of the Swift Package
/// Registry Service Specification.
///
/// A `PackageRelease` is the JSON document submitted alongside a source
/// archive when publishing a new release (§4.6, endpoint `PUT
/// /{scope}/{name}/{version}`), and is returned as the `metadata` field in
/// the release-info response (§4.2, endpoint `GET
/// /{scope}/{name}/{version}`).
///
/// All properties are optional: clients may supply as much or as little
/// metadata as they have available. When submitting metadata, the
/// `Content-Type` of the `metadata` multipart part MUST be
/// `application/json`.
public struct PackageRelease: Codable, Hashable, Sendable {
    /// The package release's author. See ``Author``.
    public var author: Author?

    /// A free-form, human-readable description of the package release.
    public var description: String?

    /// URL of the package release's license document.
    public var licenseURL: URL?

    /// URL of the README for this release (or broadly for the package).
    public var readmeURL: URL?

    /// Code repository URL(s) for the package release.
    ///
    /// It is recommended to include all URL variations (for example, both
    /// SSH and HTTPS) that refer to the same repository. This may be an
    /// empty array if the package has no source control representation.
    public var repositoryURLs: [URL]?

    /// Original publication time of the package release. Set if the release
    /// was previously published elsewhere (for example, on a different
    /// registry). Encoded as an ISO 8601 timestamp.
    public var originalPublicationTime: Date?

    /// Author of a package release.
    ///
    /// The author's ``name`` is required; all other fields are optional.
    public struct Author: Codable, Hashable, Sendable {
        /// Name of the author. Required.
        public var name: String
        /// Email address of the author.
        public var email: String?
        /// A free-form, human-readable description of the author.
        public var description: String?
        /// Organization that the author belongs to. See ``Organization``.
        public var organization: Organization?
        /// URL of the author (for example, a personal website or profile
        /// page).
        public var url: URL?

        /// Creates an `Author` value.
        ///
        /// - Parameters:
        ///   - name: The author's name. Required.
        ///   - email: The author's email address, if known.
        ///   - description: A free-form description of the author.
        ///   - organization: The organization the author belongs to.
        ///   - url: A URL identifying the author.
        public init(
            name: String,
            email: String? = nil,
            description: String? = nil,
            organization: Organization? = nil,
            url: URL? = nil
        ) {
            self.name = name
            self.email = email
            self.description = description
            self.organization = organization
            self.url = url
        }

        /// Organization that an ``Author`` belongs to.
        ///
        /// The organization's ``name`` is required; all other fields are
        /// optional.
        public struct Organization: Codable, Hashable, Sendable {
            /// Name of the organization. Required.
            public var name: String
            /// Email address of the organization.
            public var email: String?
            /// A free-form, human-readable description of the organization.
            public var description: String?
            /// URL of the organization's website.
            public var url: URL?

            /// Creates an `Organization` value.
            ///
            /// - Parameters:
            ///   - name: The organization's name. Required.
            ///   - email: The organization's email address, if known.
            ///   - description: A free-form description of the
            ///     organization.
            ///   - url: The organization's website URL.
            public init(
                name: String,
                email: String? = nil,
                description: String? = nil,
                url: URL? = nil
            ) {
                self.name = name
                self.email = email
                self.description = description
                self.url = url
            }
        }
    }

    /// Creates a `PackageRelease` value.
    ///
    /// All parameters are optional; omit any that are unknown or not
    /// applicable.
    ///
    /// - Parameters:
    ///   - author: The release's author.
    ///   - description: A free-form description of the release.
    ///   - licenseURL: URL of the release's license document.
    ///   - readmeURL: URL of the release's README.
    ///   - repositoryURLs: Source repository URLs for the release.
    ///   - originalPublicationTime: Timestamp of the release's original
    ///     publication elsewhere, if applicable.
    public init(
        author: Author? = nil,
        description: String? = nil,
        licenseURL: URL? = nil,
        readmeURL: URL? = nil,
        repositoryURLs: [URL]? = nil,
        originalPublicationTime: Date? = nil
    ) {
        self.author = author
        self.description = description
        self.licenseURL = licenseURL
        self.readmeURL = readmeURL
        self.repositoryURLs = repositoryURLs
        self.originalPublicationTime = originalPublicationTime
    }
}
