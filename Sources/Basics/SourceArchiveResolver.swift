//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

import struct TSCUtility.Version

/// A resolved git tag with its name, the commit SHA it points to, and the
/// parsed semantic version (so callers don't need to re-parse it).
public struct ResolvedTag: Equatable, Sendable {
    /// The tag name (e.g. "1.2.3" or "v1.2.3").
    public let name: String

    /// The commit SHA the tag resolves to. For annotated tags this is the
    /// dereferenced (peeled) commit SHA, not the tag object SHA.
    public let commitSHA: String

    /// The semantic version parsed from the tag name.
    public let version: Version

    public init(name: String, commitSHA: String, version: Version) {
        self.name = name
        self.commitSHA = commitSHA
        self.version = version
    }

}

/// Resolves tags, fetches manifests, and probes for submodules and manifest
/// variants using a ``SourceArchiveProvider`` for URL construction.
///
/// This resolver is provider-agnostic: any host that conforms to
/// ``SourceArchiveProvider`` can be used (e.g. GitHub, GitLab, etc.).
public struct SourceArchiveResolver: Sendable {
    private let httpClient: HTTPClient
    private let authorizationProvider: AuthorizationProvider?
    private let tagsProvider: @Sendable (String) async throws -> [ResolvedTag]
    private let tagMemoizer: ThrowingAsyncKeyValueMemoizer<String, [ResolvedTag]>

    public init(
        httpClient: HTTPClient,
        authorizationProvider: AuthorizationProvider? = nil,
        tagsProvider: (@Sendable (String) async throws -> [ResolvedTag])? = nil,
        tagMemoizer: ThrowingAsyncKeyValueMemoizer<String, [ResolvedTag]>? = nil
    ) {
        self.httpClient = httpClient
        self.authorizationProvider = authorizationProvider
        self.tagsProvider = tagsProvider ?? Self.makeHTTPTagsProvider(
            httpClient: httpClient,
            authorizationProvider: authorizationProvider
        )
        self.tagMemoizer = tagMemoizer ?? ThrowingAsyncKeyValueMemoizer()
    }

    /// Discovers semver tags for the repository at the given URL using
    /// HTTP git protocol v2.
    ///
    /// Annotated tags are peeled to their commit SHAs. Only tags that parse
    /// as valid semantic versions (with optional leading "v") are included.
    public func getTags(for url: SourceControlURL) async throws -> [ResolvedTag] {
        let key = url.absoluteString
        return try await tagMemoizer.memoize(key) { [tagsProvider] in
            try await tagsProvider(key)
        }
    }

    public func fetchManifest(
        provider: some SourceArchiveProvider,
        sha: String
    ) async throws -> String {
        try await fetchManifestFile(provider: provider, sha: sha, filename: "Package.swift")
    }

    /// Fetches the content of a manifest file (e.g. `Package.swift` or a
    /// `Package@swift-X.Y.swift` variant) at the given commit SHA.
    public func fetchManifestFile(
        provider: some SourceArchiveProvider,
        sha: String,
        filename: String
    ) async throws -> String {
        let url = provider.rawFileURL(for: filename, sha: sha)
        var options = HTTPClientRequest.Options()
        options.authorizationProvider = authorizationProvider?.httpAuthorizationHeader(for:)
        let response = try await httpClient.get(url, options: options)
        guard response.statusCode == 200, let body = response.body else {
            throw SourceArchiveResolverError.manifestNotFound(sha: sha, filename: filename)
        }
        guard let content = String(data: body, encoding: .utf8) else {
            throw SourceArchiveResolverError.invalidManifestEncoding(sha: sha)
        }
        return content
    }

    /// Checks whether the repository contains a `.gitmodules` file with actual
    /// submodule entries at the given commit SHA.
    ///
    /// Uses GET instead of HEAD to detect empty `.gitmodules` files (which exist
    /// in some repos but indicate no active submodules).
    ///
    /// - Returns: `true` if `.gitmodules` exists and contains `[submodule` entries.
    public func hasSubmodules(
        provider: some SourceArchiveProvider,
        sha: String
    ) async throws -> Bool {
        let url = provider.rawFileURL(for: ".gitmodules", sha: sha)
        var options = HTTPClientRequest.Options()
        options.authorizationProvider = authorizationProvider?.httpAuthorizationHeader(for:)
        let response = try await httpClient.get(url, options: options)
        switch response.statusCode {
        case 200:
            // Empty .gitmodules files exist in some repos — treat as no submodules
            guard let body = response.body, !body.isEmpty else { return false }
            guard let content = String(data: body, encoding: .utf8) else { return false }
            return content.contains("[submodule")
        case 404:
            return false
        default:
            throw SourceArchiveResolverError.unexpectedHTTPStatus(
                response.statusCode,
                url: url
            )
        }
    }



    /// Probes for a tools-version-specific manifest variant at the given commit
    /// SHA using HEAD requests.
    ///
    /// Checks in order: `Package@swift-X.Y.Z.swift`, `Package@swift-X.Y.swift`,
    /// `Package@swift-X.swift`. Returns the first filename that gets a 200
    /// response, or `nil` if none exist.
    public func probeManifestVariant(
        provider: some SourceArchiveProvider,
        sha: String,
        swiftVersion: Version
    ) async throws -> String? {
        // Candidates ordered by specificity (most specific first).
        let candidates = [
            "Package@swift-\(swiftVersion.major).\(swiftVersion.minor).\(swiftVersion.patch).swift",
            "Package@swift-\(swiftVersion.major).\(swiftVersion.minor).swift",
            "Package@swift-\(swiftVersion.major).swift",
        ]

        // Transport errors and non-200/404 status codes propagate as errors
        // to avoid silently falling back to the base manifest.
        let results: [(index: Int, exists: Bool)] = try await withThrowingTaskGroup(
            of: (index: Int, exists: Bool).self
        ) { group in
            for (index, candidate) in candidates.enumerated() {
                group.addTask {
                    let url = provider.rawFileURL(for: candidate, sha: sha)
                    var headOptions = HTTPClientRequest.Options()
                    headOptions.authorizationProvider = self.authorizationProvider?.httpAuthorizationHeader(for:)
                    let response = try await self.httpClient.head(url, options: headOptions)
                    switch response.statusCode {
                    case 200:
                        return (index, true)
                    case 404:
                        return (index, false)
                    default:
                        throw SourceArchiveResolverError.unexpectedHTTPStatus(
                            response.statusCode,
                            url: url
                        )
                    }
                }
            }
            var collected: [(index: Int, exists: Bool)] = []
            for try await result in group {
                collected.append(result)
            }
            return collected
        }

        let existing = results.filter(\.exists).sorted(by: { $0.index < $1.index })
        guard let best = existing.first else { return nil }
        return candidates[best.index]
    }

    // MARK: - HTTP Git Protocol v2

    /// Creates a tags provider that fetches tags via HTTP git protocol v2
    /// POST to `git-upload-pack`, parsing the pkt-line response directly
    /// into `[ResolvedTag]`.
    private static func makeHTTPTagsProvider(
        httpClient: HTTPClient,
        authorizationProvider: AuthorizationProvider?
    ) -> @Sendable (String) async throws -> [ResolvedTag] {
        { @Sendable url in
            guard let urls = GitHTTPProtocolV2.makeSmartHTTPURLs(from: url) else {
                throw SourceArchiveResolverError.httpGitProtocolFailed(
                    statusCode: 0, url: url)
            }

            var headers = HTTPClientHeaders()
            headers.add(name: "Git-Protocol", value: "version=2")
            headers.add(name: "Accept-Encoding", value: "deflate, gzip")

            // Try without credentials first (public repos), retry with auth on 401.
            var options = HTTPClientRequest.Options()
            var discovery = try await httpClient.get(urls.infoRefs, headers: headers, options: options)

            if discovery.statusCode == 401, authorizationProvider != nil {
                options.authorizationProvider = authorizationProvider?.httpAuthorizationHeader(for:)
                discovery = try await httpClient.get(urls.infoRefs, headers: headers, options: options)
            }

            guard discovery.statusCode == 200 else {
                throw SourceArchiveResolverError.httpGitProtocolFailed(
                    statusCode: discovery.statusCode, url: url)
            }
            let discoveryLines = PktLine.decode(discovery.body ?? Data())
            guard discoveryLines.contains(where: { $0.hasPrefix("version 2") }) else {
                throw SourceArchiveResolverError.httpGitProtocolFailed(
                    statusCode: discovery.statusCode, url: url)
            }

            headers.add(name: "Content-Type", value: "application/x-git-upload-pack-request")
            headers.add(name: "Accept", value: "application/x-git-upload-pack-result")

            let response = try await httpClient.post(
                urls.uploadPack,
                body: GitHTTPProtocolV2.makeTagRefsRequestBody(serverCapabilities: discoveryLines),
                headers: headers,
                options: options
            )

            guard response.statusCode == 200, let body = response.body else {
                throw SourceArchiveResolverError.httpGitProtocolFailed(
                    statusCode: response.statusCode, url: url)
            }

            let lines = PktLine.decode(body)
            if let err = lines.first(where: { $0.hasPrefix("ERR ") }) {
                throw SourceArchiveResolverError.httpGitProtocolFailed(
                    statusCode: response.statusCode, url: "\(url): \(err)")
            }
            return GitHTTPProtocolV2.resolvedTags(from: lines)
        }
    }

}

// MARK: - Errors

public enum SourceArchiveResolverError: Error, CustomStringConvertible {
    case manifestNotFound(sha: String, filename: String)
    case invalidManifestEncoding(sha: String)
    case unexpectedHTTPStatus(Int, url: URL)
    case httpGitProtocolFailed(statusCode: Int, url: String)

    public var description: String {
        switch self {
        case .manifestNotFound(let sha, let filename):
            return "\(filename) not found at commit \(sha)"
        case .invalidManifestEncoding(let sha):
            return "Package.swift at commit \(sha) is not valid UTF-8"
        case .unexpectedHTTPStatus(let code, let url):
            return "Unexpected HTTP status \(code) for \(url)"
        case .httpGitProtocolFailed(let statusCode, let url):
            return "HTTP git protocol v2 ls-refs failed with status \(statusCode) for \(url)"
        }
    }
}
