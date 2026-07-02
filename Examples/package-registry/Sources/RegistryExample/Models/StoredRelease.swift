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

/// A single package release as held in the registry's storage layer.
///
/// A `StoredRelease` bundles everything needed to serve the registry
/// endpoints defined in §4 of the Swift Package Registry Service
/// Specification for a particular `{scope}/{name}/{version}` tuple:
///
/// - §4.1 *List package releases*: the presence of a `StoredRelease`
///   entry marks a version as available.
/// - §4.2 *Fetch release metadata*: served from ``metadata`` /
///   ``metadataRaw``, ``sourceArchiveChecksum``, and ``publishedAt``.
/// - §4.3 *Fetch manifest*: served from ``manifests``, which maps
///   manifest filenames to their contents.
/// - §4.4 *Download source archive*: served from ``sourceArchive``,
///   verified by ``sourceArchiveChecksum``.
///
/// Values of this type are immutable snapshots of a release; creating or
/// modifying a release produces a new value.
public struct StoredRelease: Sendable, Hashable {
    /// The package this release belongs to.
    public let identifier: PackageIdentifier
    /// The SemVer version identifying this release.
    public let version: PackageVersion
    /// The raw bytes of the release's source archive, served by §4.4
    /// (`GET /{scope}/{name}/{version}.zip`) with content type
    /// `application/zip`.
    public let sourceArchive: Data
    /// A cryptographic digest of ``sourceArchive`` (for example,
    /// `"sha-256=..."`). Returned as the `checksum` of the
    /// `source-archive` resource in the §4.2 release-info response and
    /// used by clients to verify downloads from §4.4.
    public let sourceArchiveChecksum: String
    /// The manifest files contained in the release, keyed by filename.
    ///
    /// The default manifest is stored under the key `"Package.swift"`;
    /// Swift-version-qualified variants use keys of the form
    /// `"Package@swift-{version}.swift"`. This map backs §4.3
    /// (`GET /{scope}/{name}/{version}/Package.swift{?swift-version}`).
    public let manifests: [String: String]
    /// The decoded release metadata supplied at publish time, or `nil`
    /// if the publisher did not provide a metadata document. Returned as
    /// the `metadata` field in the §4.2 response.
    public let metadata: PackageRelease?
    /// The original, unmodified bytes of the metadata JSON document as
    /// supplied by the publisher, preserved so that the exact payload
    /// (including whitespace and field ordering) can be round-tripped to
    /// clients. `nil` when no metadata was supplied.
    public let metadataRaw: Data?
    /// The timestamp at which this release was accepted by the registry.
    public let publishedAt: Date
    /// The raw bytes of the `source-archive-signature` multipart part, or
    /// `nil` if the release was published unsigned. Interpretation is
    /// dictated by ``signatureFormat``.
    public let sourceArchiveSignature: Data?
    /// The raw bytes of the `metadata-signature` multipart part, or `nil`
    /// if no metadata signature was supplied. Only meaningful when
    /// ``metadataRaw`` is non-nil.
    public let metadataSignature: Data?
    /// The value of the `X-Swift-Package-Signature-Format` header at
    /// publish time (for example, `"cms-1.0.0"`), or `nil` if the release
    /// was published unsigned.
    public let signatureFormat: String?

    /// Creates a `StoredRelease` snapshot.
    ///
    /// - Parameters:
    ///   - identifier: The package this release belongs to.
    ///   - version: The SemVer version of the release.
    ///   - sourceArchive: The raw bytes of the `.zip` source archive.
    ///   - sourceArchiveChecksum: The cryptographic digest of
    ///     `sourceArchive`, in the `"sha-256=..."` form used by §4.2.
    ///   - manifests: Manifest filenames mapped to their contents.
    ///     Must include a `"Package.swift"` entry for the default
    ///     manifest; may also include `"Package@swift-{version}.swift"`
    ///     entries.
    ///   - metadata: The decoded ``PackageRelease`` metadata, or `nil` if
    ///     none was supplied.
    ///   - metadataRaw: The raw bytes of the metadata JSON exactly as
    ///     submitted, or `nil` if none was supplied.
    ///   - publishedAt: The timestamp at which the release was accepted.
    ///   - sourceArchiveSignature: Raw bytes of the
    ///     `source-archive-signature` multipart part, if the publisher
    ///     supplied one.
    ///   - metadataSignature: Raw bytes of the `metadata-signature`
    ///     multipart part, if the publisher supplied one.
    ///   - signatureFormat: The value of the
    ///     `X-Swift-Package-Signature-Format` request header, if any
    ///     signature part was present.
    public init(
        identifier: PackageIdentifier,
        version: PackageVersion,
        sourceArchive: Data,
        sourceArchiveChecksum: String,
        manifests: [String: String],
        metadata: PackageRelease?,
        metadataRaw: Data?,
        publishedAt: Date,
        sourceArchiveSignature: Data? = nil,
        metadataSignature: Data? = nil,
        signatureFormat: String? = nil
    ) {
        self.identifier = identifier
        self.version = version
        self.sourceArchive = sourceArchive
        self.sourceArchiveChecksum = sourceArchiveChecksum
        self.manifests = manifests
        self.metadata = metadata
        self.metadataRaw = metadataRaw
        self.publishedAt = publishedAt
        self.sourceArchiveSignature = sourceArchiveSignature
        self.metadataSignature = metadataSignature
        self.signatureFormat = signatureFormat
    }
}
