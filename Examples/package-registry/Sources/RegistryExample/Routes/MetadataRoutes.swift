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

/// Route handlers for the read-only package registry endpoints defined in
/// §4.1 through §4.4 of the Swift Package Registry Service Specification:
///
/// - §4.1 `GET /{scope}/{name}`: list package releases.
/// - §4.2 `GET /{scope}/{name}/{version}`: fetch release metadata.
/// - §4.3 `GET /{scope}/{name}/{version}/Package.swift{?swift-version}`:
///   fetch the package manifest, with optional Swift-version selection.
/// - §4.4 `GET /{scope}/{name}/{version}.zip`: download the source
///   archive.
///
/// The §4.2 and §4.4 endpoints share the same path prefix; this type
/// routes between them based on whether the `{version}` segment ends in
/// `.zip`.
///
/// Successful responses include the `Link` headers required by the
/// specification: a `latest-version` link on list/metadata responses,
/// `predecessor-version`/`successor-version` links on release info
/// responses, and `alternate` links to any Swift-version-qualified
/// manifest variants on the manifest response.
public struct MetadataRoutes: Sendable {
    static let defaultPageSize = 50

    let store: RegistryStore

    /// Creates a `MetadataRoutes` handler backed by the given store.
    ///
    /// - Parameter store: The registry store used to look up releases.
    public init(store: RegistryStore) {
        self.store = store
    }

    /// Registers the §4.1-§4.4 read endpoints on the supplied router.
    ///
    /// Registers `GET /{scope}/{name}`, `GET /{scope}/{name}/{version}`
    /// (which also serves `.zip` downloads via ``releaseOrArchive(req:)``),
    /// and `GET /{scope}/{name}/{version}/Package.swift`.
    ///
    /// - Parameter router: The Vapor routes builder to attach the handlers
    ///   to.
    public func register(_ router: any RoutesBuilder) {
        router.get(":scope", ":name", use: listReleases)
        router.get(":scope", ":name", ":version", use: releaseOrArchive)
        router.get(":scope", ":name", ":version", "Package.swift", use: manifest)
    }

    @Sendable
    func listReleases(req: Request) async throws -> Response {
        let rawScope = try req.parameters.require("scope")
        let rawName = try req.parameters.require("name")
        let name = stripJSONSuffix(rawName)
        let identifier = try parseIdentifier(scope: rawScope, name: name)
        guard let releases = await store.list(identifier), !releases.isEmpty else {
            throw ProblemDetails.notFound("package not found")
        }
        let page = try parsePage(req)
        let pageSize = Self.defaultPageSize
        let totalPages = (releases.count + pageSize - 1) / pageSize
        guard page <= totalPages else {
            throw ProblemDetails.notFound("page not found")
        }
        let start = (page - 1) * pageSize
        let end = min(start + pageSize, releases.count)
        let pageReleases = releases[start..<end]
        let baseURL = req.baseURL
        var orderedReleases: [String: [String: String]] = [:]
        for release in pageReleases {
            let url = "\(baseURL)/\(identifier.scope)/\(identifier.name)/\(release.version)"
            orderedReleases[release.version.description] = ["url": url]
        }
        let response = try encodeJSON(ListReleasesResponse(releases: orderedReleases))
        var links: [String] = []
        if let latest = releases.first {
            links.append("<\(baseURL)/\(identifier.scope)/\(identifier.name)/\(latest.version)>; rel=\"latest-version\"")
            links.append(contentsOf: repositoryLinks(from: latest.metadata))
        }
        links.append(contentsOf: paginationLinks(
            baseURL: baseURL,
            identifier: identifier,
            page: page,
            totalPages: totalPages
        ))
        if !links.isEmpty {
            response.headers.replaceOrAdd(name: .link, value: links.joined(separator: ", "))
        }
        return response
    }

    private func parsePage(_ req: Request) throws -> Int {
        guard let raw = try? req.query.get(String.self, at: "page") else { return 1 }
        guard let page = Int(raw), page >= 1 else {
            throw ProblemDetails.badRequest("invalid page parameter")
        }
        return page
    }

    private func paginationLinks(
        baseURL: String,
        identifier: PackageIdentifier,
        page: Int,
        totalPages: Int
    ) -> [String] {
        guard totalPages > 1 else { return [] }
        let pageURL = { (n: Int) in
            "\(baseURL)/\(identifier.scope)/\(identifier.name)?page=\(n)"
        }
        var links = ["<\(pageURL(1))>; rel=\"first\""]
        if page > 1 {
            links.append("<\(pageURL(page - 1))>; rel=\"prev\"")
        }
        if page < totalPages {
            links.append("<\(pageURL(page + 1))>; rel=\"next\"")
        }
        links.append("<\(pageURL(totalPages))>; rel=\"last\"")
        return links
    }

    private func repositoryLinks(from metadata: PackageRelease?) -> [String] {
        guard let urls = metadata?.repositoryURLs, let canonical = urls.first else {
            return []
        }
        var links = ["<\(canonical)>; rel=\"canonical\""]
        for alternate in urls.dropFirst() {
            links.append("<\(alternate)>; rel=\"alternate\"")
        }
        return links
    }

    @Sendable
    func releaseOrArchive(req: Request) async throws -> Response {
        let rawVersion = try req.parameters.require("version")
        if rawVersion.hasSuffix(".zip") {
            return try await sourceArchive(req: req, trimmedVersion: String(rawVersion.dropLast(4)))
        }
        return try await releaseInfo(req: req, trimmedVersion: stripJSONSuffix(rawVersion))
    }

    private func releaseInfo(req: Request, trimmedVersion: String) async throws -> Response {
        let identifier = try parseIdentifier(
            scope: try req.parameters.require("scope"),
            name: try req.parameters.require("name")
        )
        let version = try parseVersion(trimmedVersion)
        guard let release = await store.get(identifier, version: version) else {
            throw ProblemDetails.notFound("release not found")
        }
        let archiveSigning: ReleaseInfoResponse.Signing? = {
            guard let sig = release.sourceArchiveSignature,
                  let format = release.signatureFormat else { return nil }
            return .init(signatureBase64Encoded: sig.base64EncodedString(), signatureFormat: format)
        }()
        let body = ReleaseInfoResponse(
            id: "\(identifier.scope).\(identifier.name)",
            version: release.version.description,
            resources: [
                .init(
                    name: "source-archive",
                    type: "application/zip",
                    checksum: release.sourceArchiveChecksum,
                    signing: archiveSigning
                )
            ],
            metadata: release.metadata,
            publishedAt: ISO8601DateFormatter.fractionalString(for: release.publishedAt)
        )
        let response = try encodeJSON(body)
        if let releases = await store.list(identifier) {
            let baseURL = req.baseURL
            var links: [String] = []
            if let latest = releases.first {
                links.append("<\(baseURL)/\(identifier.scope)/\(identifier.name)/\(latest.version)>; rel=\"latest-version\"")
            }
            let sorted = releases.sorted { $0.version < $1.version }
            if let idx = sorted.firstIndex(where: { $0.version == release.version }) {
                if idx > 0 {
                    links.append("<\(baseURL)/\(identifier.scope)/\(identifier.name)/\(sorted[idx - 1].version)>; rel=\"predecessor-version\"")
                }
                if idx < sorted.count - 1 {
                    links.append("<\(baseURL)/\(identifier.scope)/\(identifier.name)/\(sorted[idx + 1].version)>; rel=\"successor-version\"")
                }
            }
            if !links.isEmpty {
                response.headers.replaceOrAdd(name: .link, value: links.joined(separator: ", "))
            }
        }
        return response
    }

    private func sourceArchive(req: Request, trimmedVersion: String) async throws -> Response {
        let identifier = try parseIdentifier(
            scope: try req.parameters.require("scope"),
            name: try req.parameters.require("name")
        )
        let version = try parseVersion(trimmedVersion)
        guard let release = await store.get(identifier, version: version) else {
            throw ProblemDetails.notFound("release not found")
        }
        let response = Response(status: .ok, body: .init(data: release.sourceArchive))
        response.headers.replaceOrAdd(name: .contentType, value: "application/zip")
        let filename = "\(identifier.name)-\(version).zip"
        response.headers.replaceOrAdd(
            name: .contentDisposition,
            value: "attachment; filename=\"\(filename)\""
        )
        response.headers.replaceOrAdd(name: "Accept-Ranges", value: "bytes")
        response.headers.replaceOrAdd(name: .cacheControl, value: "public, immutable")
        response.headers.replaceOrAdd(
            name: "Digest",
            value: "sha-256=\(base64Digest(of: release.sourceArchive))"
        )
        if let sig = release.sourceArchiveSignature, let format = release.signatureFormat {
            response.headers.replaceOrAdd(name: "X-Swift-Package-Signature-Format", value: format)
            response.headers.replaceOrAdd(
                name: "X-Swift-Package-Signature",
                value: sig.base64EncodedString()
            )
        }
        return response
    }

    @Sendable
    func manifest(req: Request) async throws -> Response {
        let identifier = try parseIdentifier(
            scope: try req.parameters.require("scope"),
            name: try req.parameters.require("name")
        )
        let version = try parseVersion(try req.parameters.require("version"))
        guard let release = await store.get(identifier, version: version) else {
            throw ProblemDetails.notFound("release not found")
        }
        let swiftVersion = (try? req.query.get(String.self, at: "swift-version")) ?? ""
        guard let contents = release.manifests[swiftVersion] else {
            let baseURL = req.baseURL
            let response = Response(status: .seeOther)
            response.headers.replaceOrAdd(
                name: .location,
                value: "\(baseURL)/\(identifier.scope)/\(identifier.name)/\(version)/Package.swift"
            )
            return response
        }
        let filename = swiftVersion.isEmpty ? "Package.swift" : "Package@swift-\(swiftVersion).swift"
        let response = Response(status: .ok, body: .init(string: contents))
        response.headers.replaceOrAdd(name: .contentType, value: "text/x-swift")
        response.headers.replaceOrAdd(
            name: .contentDisposition,
            value: "attachment; filename=\"\(filename)\""
        )
        response.headers.replaceOrAdd(name: .cacheControl, value: "public, immutable")

        let alternateLinks = release.manifests
            .filter { !$0.key.isEmpty }
            .sorted { $0.key < $1.key }
            .map { key, manifest -> String in
                let alternateFilename = "Package@swift-\(key).swift"
                let toolsVersion = extractToolsVersion(from: manifest) ?? key
                let baseURL = req.baseURL
                let url = "\(baseURL)/\(identifier.scope)/\(identifier.name)/\(version)/Package.swift?swift-version=\(key)"
                return "<\(url)>; rel=\"alternate\"; filename=\"\(alternateFilename)\"; swift-tools-version=\"\(toolsVersion)\""
            }
        if !alternateLinks.isEmpty {
            response.headers.replaceOrAdd(name: .link, value: alternateLinks.joined(separator: ", "))
        }
        return response
    }

    private func stripJSONSuffix(_ raw: String) -> String {
        raw.hasSuffix(".json") ? String(raw.dropLast(5)) : raw
    }

    private func parseIdentifier(scope: String, name: String) throws -> PackageIdentifier {
        do {
            return try PackageIdentifier(scope: scope, name: name)
        } catch PackageIdentifierError.invalidScope {
            throw ProblemDetails.badRequest("invalid package scope")
        } catch PackageIdentifierError.invalidName {
            throw ProblemDetails.badRequest("invalid package name")
        }
    }

    private func parseVersion(_ raw: String) throws -> PackageVersion {
        do { return try PackageVersion(raw) }
        catch { throw ProblemDetails.badRequest("invalid version") }
    }

    private func encodeJSON<T: Encodable>(_ body: T) throws -> Response {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(body)
        let response = Response(status: .ok, body: .init(data: data))
        response.headers.replaceOrAdd(name: .contentType, value: "application/json")
        return response
    }

    private func extractToolsVersion(from manifest: String) -> String? {
        guard let firstLine = manifest.split(separator: "\n").first else { return nil }
        let prefix = "// swift-tools-version:"
        guard let range = firstLine.range(of: prefix) else { return nil }
        let value = firstLine[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    private func base64Digest(of data: Data) -> String {
        Data(CryptoDigest.sha256(data)).base64EncodedString()
    }
}

import CryptoKit

enum CryptoDigest {
    static func sha256(_ data: Data) -> [UInt8] {
        Array(SHA256.hash(data: data))
    }
}

struct ListReleasesResponse: Codable {
    var releases: [String: [String: String]]
}

struct ReleaseInfoResponse: Encodable {
    struct Signing: Codable {
        var signatureBase64Encoded: String
        var signatureFormat: String
    }
    struct Resource: Codable {
        var name: String
        var type: String
        var checksum: String
        var signing: Signing?
    }
    var id: String
    var version: String
    var resources: [Resource]
    var metadata: PackageRelease?
    var publishedAt: String

    enum CodingKeys: String, CodingKey {
        case id, version, resources, metadata, publishedAt
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(version, forKey: .version)
        try c.encode(resources, forKey: .resources)
        try c.encode(metadata ?? PackageRelease(), forKey: .metadata)
        try c.encode(publishedAt, forKey: .publishedAt)
    }
}

extension ISO8601DateFormatter {
    static func fractionalString(for date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
}
