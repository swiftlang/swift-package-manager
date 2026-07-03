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
import CryptoKit
import NIOCore

/// Errors that ``ReleasePublisher/publish(identifier:version:body:contentType:signatureFormat:)``
/// can throw.
///
/// Each case names a distinct rejection reason that the caller (typically
/// the publish route) translates into a `ProblemDetails` response. The
/// publisher catches lower-level errors from the multipart parser, the
/// manifest extractor, JSON decoding, and the registry store, and surfaces
/// them as values of this type so the publishing rules are described by a
/// single, finite vocabulary at the seam.
public enum PublishError: Error, Equatable, Sendable {
    /// A release with the same identifier and SemVer precedence key has
    /// already been published. Surfaced as `409 Conflict`.
    case conflict
    /// The multipart body did not include a `source-archive` part.
    case missingArchive
    /// The bytes of the `source-archive` part could not be opened as a
    /// readable zip.
    case invalidArchive
    /// The archive does not contain a `Package.swift` manifest at depth 1
    /// or 2.
    case manifestMissing
    /// A manifest entry exceeded the configured decompressed-size cap.
    case manifestTooLarge
    /// The `metadata` part was present but its body could not be decoded
    /// as a ``PackageRelease``.
    case invalidMetadataJSON
    /// The body was framed correctly but could not be parsed by the
    /// multipart parser.
    case malformedMultipart
    /// The request's `Content-Type` did not include a `boundary=...`
    /// parameter.
    case missingMultipartBoundary
    /// A `metadata-signature` part was supplied without a corresponding
    /// `metadata` part.
    case metadataSignatureRequiresMetadata
    /// One of the signature parts was supplied without an
    /// `X-Swift-Package-Signature-Format` header.
    case signaturePartRequiresFormat
    /// An `X-Swift-Package-Signature-Format` header was supplied without
    /// a corresponding signature part.
    case signatureFormatRequiresPart
    /// The signature format named by the
    /// `X-Swift-Package-Signature-Format` header is not in the
    /// publisher's supported set.
    case unsupportedSignatureFormat(String)
}

/// Performs `PUT /{scope}/{name}/{version}` (§4.6 *Create a package
/// release*) end to end behind a single interface.
///
/// `ReleasePublisher` parses the multipart body, extracts the package's
/// manifests, computes the source archive checksum, decodes optional
/// metadata, validates the signature header rules, and commits the
/// resulting ``StoredRelease`` to the supplied ``RegistryStore``. The
/// publish route is a thin HTTP adapter over this interface, responsible
/// only for parameter validation and translating ``PublishError`` cases
/// into ``ProblemDetails`` responses.
///
/// Inputs are trusted: the caller is expected to validate the
/// ``PackageIdentifier`` and ``PackageVersion`` ahead of time and to
/// confirm the body is non-empty.
public struct ReleasePublisher: Sendable {
    static let supportedSignatureFormats: Set<String> = ["cms-1.0.0"]

    let store: RegistryStore

    /// Creates a publisher backed by the given store.
    public init(store: RegistryStore) {
        self.store = store
    }

    /// Publishes a new release.
    ///
    /// - Parameters:
    ///   - identifier: The validated package identifier.
    ///   - version: The validated SemVer version.
    ///   - body: The raw multipart request body bytes.
    ///   - contentType: The request's `Content-Type` header value.
    ///     Required to extract the multipart boundary.
    ///   - signatureFormat: The value of the
    ///     `X-Swift-Package-Signature-Format` request header, if any.
    /// - Returns: The ``StoredRelease`` that was committed to the store.
    /// - Throws: ``PublishError`` for any rejection reason. No other
    ///   error type crosses this seam.
    public func publish(
        identifier: PackageIdentifier,
        version: PackageVersion,
        body: ByteBuffer,
        contentType: String,
        signatureFormat: String?
    ) async throws -> StoredRelease {
        if await store.get(identifier, version: version) != nil {
            throw PublishError.conflict
        }

        let parts: [ParsedMultipartPart]
        do {
            parts = try PublishMultipartParser.parse(body: body, contentType: contentType)
        } catch MultipartParseError.missingBoundary {
            throw PublishError.missingMultipartBoundary
        } catch {
            throw PublishError.malformedMultipart
        }

        guard let archivePart = parts.first(where: { $0.name == "source-archive" }) else {
            throw PublishError.missingArchive
        }

        let manifests: [String: String]
        do {
            manifests = try ManifestExtractor.extract(from: archivePart.data)
        } catch ManifestExtractorError.invalidArchive {
            throw PublishError.invalidArchive
        } catch ManifestExtractorError.manifestMissing {
            throw PublishError.manifestMissing
        } catch ManifestExtractorError.manifestTooLarge {
            throw PublishError.manifestTooLarge
        }

        let checksum = SHA256.hash(data: archivePart.data)
            .map { String(format: "%02x", $0) }
            .joined()

        var metadata: PackageRelease?
        var metadataRaw: Data?
        if let metaPart = parts.first(where: { $0.name == "metadata" }) {
            metadataRaw = metaPart.data
            do {
                metadata = try JSONDecoder.registry.decode(PackageRelease.self, from: metaPart.data)
            } catch {
                throw PublishError.invalidMetadataJSON
            }
        }

        let archiveSignature = parts.first(where: { $0.name == "source-archive-signature" })?.data
        let metadataSignature = parts.first(where: { $0.name == "metadata-signature" })?.data

        if metadataSignature != nil, metadataRaw == nil {
            throw PublishError.metadataSignatureRequiresMetadata
        }

        let hasAnySignature = archiveSignature != nil || metadataSignature != nil
        if hasAnySignature && signatureFormat == nil {
            throw PublishError.signaturePartRequiresFormat
        }
        if signatureFormat != nil && !hasAnySignature {
            throw PublishError.signatureFormatRequiresPart
        }
        if let format = signatureFormat, !Self.supportedSignatureFormats.contains(format) {
            throw PublishError.unsupportedSignatureFormat(format)
        }

        let release = StoredRelease(
            identifier: identifier,
            version: version,
            sourceArchive: archivePart.data,
            sourceArchiveChecksum: checksum,
            manifests: manifests,
            metadata: metadata,
            metadataRaw: metadataRaw,
            publishedAt: Date(),
            sourceArchiveSignature: archiveSignature,
            metadataSignature: metadataSignature,
            signatureFormat: signatureFormat
        )

        do {
            try await store.publish(release)
        } catch RegistryStoreError.conflict {
            throw PublishError.conflict
        }

        return release
    }
}
