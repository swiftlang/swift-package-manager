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

/// A resolved git tag with its name and the commit SHA it points to.
public struct ResolvedTag: Equatable, Sendable {
    /// The tag name (e.g. "1.2.3" or "v1.2.3").
    public let name: String

    /// The commit SHA the tag resolves to. For annotated tags this is the
    /// dereferenced (peeled) commit SHA, not the tag object SHA.
    public let sha: String

    public init(name: String, sha: String) {
        self.name = name
        self.sha = sha
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
    private let gitTagsProvider: @Sendable (String) async throws -> String
    private let tagMemoizer: ThrowingAsyncKeyValueMemoizer<String, [ResolvedTag]>

    public init(
        httpClient: HTTPClient,
        authorizationProvider: AuthorizationProvider? = nil,
        gitTagsProvider: (@Sendable (String) async throws -> String)? = nil,
        tagMemoizer: ThrowingAsyncKeyValueMemoizer<String, [ResolvedTag]>? = nil
    ) {
        self.httpClient = httpClient
        self.authorizationProvider = authorizationProvider
        self.gitTagsProvider = gitTagsProvider ?? Self.defaultGitTagsProvider
        self.tagMemoizer = tagMemoizer ?? ThrowingAsyncKeyValueMemoizer()
    }

    /// Discovers semver tags for the repository at the given URL by invoking
    /// `git ls-remote --tags`.
    ///
    /// Annotated tags are peeled: when `git ls-remote` returns both a tag
    /// object ref (`refs/tags/X`) and its dereferenced commit
    /// (`refs/tags/X^{}`), the peeled commit SHA is used. Lightweight tags
    /// produce a single entry and are used as-is.
    ///
    /// Only tags that parse as valid semantic versions (with optional leading
    /// "v") are included in the result.
    public func getTags(for url: SourceControlURL) async throws -> [ResolvedTag] {
        let key = url.absoluteString
        return try await tagMemoizer.memoize(key) { [gitTagsProvider] in
            let output = try await gitTagsProvider(key)
            let rawTags = Self.parseLsRemoteOutput(output)
            let peeled = Self.peelTags(rawTags)
            return Self.filterSemverTags(peeled)
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

    // MARK: - Git ls-remote Parsing (Internal for Testing)

    /// A raw tag entry as parsed from `git ls-remote` output before peeling.
    struct RawTagRef: Equatable {
        let sha: String
        let tagName: String
        let isPeeled: Bool
    }

    /// Parses the output of `git ls-remote --tags` into raw tag references.
    ///
    /// Each line has the format: `<sha>\trefs/tags/<tagname>`, where annotated
    /// tags additionally produce a line ending in `^{}`.
    static func parseLsRemoteOutput(_ output: String) -> [RawTagRef] {
        var refs: [RawTagRef] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let sha = String(parts[0])
            guard !sha.isEmpty, sha.allSatisfy(\.isHexDigit) else { continue }
            let refPath = String(parts[1])

            guard refPath.hasPrefix("refs/tags/") else { continue }
            var tagName = String(refPath.dropFirst("refs/tags/".count))

            let isPeeled = tagName.hasSuffix("^{}")
            if isPeeled {
                tagName = String(tagName.dropLast(3))
            }

            refs.append(RawTagRef(sha: sha, tagName: tagName, isPeeled: isPeeled))
        }
        return refs
    }

    /// Resolves raw tag references by preferring peeled (dereferenced) SHAs for
    /// annotated tags. Lightweight tags keep their single SHA.
    static func peelTags(_ refs: [RawTagRef]) -> [(name: String, sha: String)] {
        // Build a dictionary keyed by tag name. Peeled entries overwrite
        // non-peeled entries so that annotated tags resolve to the commit SHA.
        var resolved: [String: String] = [:]
        // Track insertion order so callers get deterministic output.
        var orderedNames: [String] = []

        for ref in refs {
            if resolved[ref.tagName] == nil {
                orderedNames.append(ref.tagName)
            }
            if ref.isPeeled || resolved[ref.tagName] == nil {
                resolved[ref.tagName] = ref.sha
            }
        }

        return orderedNames.compactMap { name in
            guard let sha = resolved[name] else { return nil }
            return (name: name, sha: sha)
        }
    }

    /// Filters to tags that parse as valid semantic versions.
    static func filterSemverTags(
        _ tags: [(name: String, sha: String)]
    ) -> [ResolvedTag] {
        tags.compactMap { tag in
            guard Version(tag: tag.name) != nil else { return nil }
            return ResolvedTag(name: tag.name, sha: tag.sha)
        }
    }

    /// Invokes `git ls-remote --tags <url>` and returns stdout.
    @Sendable package static func defaultGitTagsProvider(url: String) async throws -> String {
        let process = AsyncProcess(
            arguments: ["git", "ls-remote", "--tags", url]
        )
        _ = try process.launch()
        let result = try await process.waitUntilExit()
        guard result.exitStatus == .terminated(code: 0) else {
            throw SourceArchiveResolverError.gitLsRemoteFailed(
                stderr: (try? result.utf8stderrOutput()) ?? "unknown error"
            )
        }
        return try result.utf8Output()
    }

}

// MARK: - Errors

public enum SourceArchiveResolverError: Error, CustomStringConvertible {
    case manifestNotFound(sha: String, filename: String)
    case invalidManifestEncoding(sha: String)
    case unexpectedHTTPStatus(Int, url: URL)
    case gitLsRemoteFailed(stderr: String)

    public var description: String {
        switch self {
        case .manifestNotFound(let sha, let filename):
            return "\(filename) not found at commit \(sha)"
        case .invalidManifestEncoding(let sha):
            return "Package.swift at commit \(sha) is not valid UTF-8"
        case .unexpectedHTTPStatus(let code, let url):
            return "Unexpected HTTP status \(code) for \(url)"
        case .gitLsRemoteFailed(let stderr):
            return "git ls-remote --tags failed: \(stderr)"
        }
    }
}
