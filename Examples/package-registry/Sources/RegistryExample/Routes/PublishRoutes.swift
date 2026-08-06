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
import Vapor

/// Route handler for §4.6 *Create a package release*
/// (`PUT /{scope}/{name}/{version}`).
///
/// The handler is a thin HTTP adapter over ``ReleasePublisher``: it
/// validates path parameters, confirms a body is present, hands the bytes
/// to the publisher, and translates ``PublishError`` cases into
/// ``ProblemDetails`` responses. On success it returns `201 Created` with
/// the `Location` header pointing at the new release.
///
/// Bodies up to 50 MiB are accepted.
public struct PublishRoutes: Sendable {
    let publisher: ReleasePublisher

    /// Creates a `PublishRoutes` handler backed by the given publisher.
    public init(publisher: ReleasePublisher) {
        self.publisher = publisher
    }

    /// Registers the `PUT /{scope}/{name}/{version}` publish route on the
    /// supplied router, configured to collect bodies up to 50 MiB.
    public func register(_ router: any RoutesBuilder) {
        router.on(.PUT, ":scope", ":name", ":version", body: .collect(maxSize: "50mb"), use: publish)
    }

    @Sendable
    func publish(req: Request) async throws -> Response {
        let scope = try req.parameters.require("scope")
        let name = try req.parameters.require("name")
        let versionString = try req.parameters.require("version")

        let identifier: PackageIdentifier
        do {
            identifier = try PackageIdentifier(scope: scope, name: name)
        } catch PackageIdentifierError.invalidScope {
            throw ProblemDetails.badRequest("invalid package scope")
        } catch PackageIdentifierError.invalidName {
            throw ProblemDetails.badRequest("invalid package name")
        }

        let version: PackageVersion
        do {
            version = try PackageVersion(versionString)
        } catch {
            throw ProblemDetails.badRequest("invalid version")
        }

        guard let body = req.body.data else {
            throw ProblemDetails.unprocessable("request body missing")
        }

        let contentType = req.headers.first(name: .contentType) ?? ""
        let signatureFormat = req.headers.first(name: "X-Swift-Package-Signature-Format")

        do {
            _ = try await publisher.publish(
                identifier: identifier,
                version: version,
                body: body,
                contentType: contentType,
                signatureFormat: signatureFormat
            )
        } catch let error as PublishError {
            throw problemDetails(for: error, version: version)
        }

        let response = Response(status: .created)
        response.headers.replaceOrAdd(
            name: .location,
            value: "\(req.baseURL)/\(identifier.scope)/\(identifier.name)/\(version)"
        )
        return response
    }

    private func problemDetails(for error: PublishError, version: PackageVersion) -> ProblemDetails {
        switch error {
        case .conflict:
            return ProblemDetails.conflict("a release with version \(version) already exists")
        case .missingArchive:
            return ProblemDetails.unprocessable("missing source-archive part")
        case .invalidArchive:
            return ProblemDetails.unprocessable("source archive is not a valid zip")
        case .manifestMissing:
            return ProblemDetails.unprocessable("package doesn't contain a valid manifest (Package.swift) file")
        case .manifestTooLarge:
            return ProblemDetails.unprocessable("manifest exceeds maximum allowed size")
        case .invalidMetadataJSON:
            return ProblemDetails.unprocessable("invalid JSON provided for release metadata")
        case .malformedMultipart:
            return ProblemDetails.unprocessable("malformed multipart body")
        case .missingMultipartBoundary:
            return ProblemDetails.unprocessable("malformed multipart body")
        case .metadataSignatureRequiresMetadata:
            return ProblemDetails.unprocessable("metadata-signature part requires a metadata part")
        case .signaturePartRequiresFormat:
            return ProblemDetails.unprocessable("signature part requires X-Swift-Package-Signature-Format header")
        case .signatureFormatRequiresPart:
            return ProblemDetails.unprocessable("X-Swift-Package-Signature-Format header requires a signature part")
        case .unsupportedSignatureFormat(let format):
            return ProblemDetails.unprocessable("unsupported signature format \"\(format)\"")
        }
    }
}
