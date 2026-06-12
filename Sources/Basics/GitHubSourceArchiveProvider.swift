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

/// A ``SourceArchiveProvider`` implementation for GitHub repositories accessed over HTTPS.
public struct GitHubSourceArchiveProvider: SourceArchiveProvider {
    public let owner: String
    public let repository: String

    public var host: String { "github.com" }

    public var cacheKey: (owner: String, repo: String) {
        (owner, repository)
    }

    public init(owner: String, repository: String) {
        self.owner = owner
        self.repository = repository
    }

    public static func make(for url: SourceControlURL) -> GitHubSourceArchiveProvider? {
        guard let (owner, repository) = parseGitHubURL(url) else { return nil }
        return GitHubSourceArchiveProvider(owner: owner, repository: repository)
    }

    /// Characters safe for a single URL path component (`.urlPathAllowed`
    /// minus `/` so that tags like `release/1.2.3` get the slash escaped).
    private static let urlPathComponentAllowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove("/")
        return set
    }()

    public func archiveURL(forSHA sha: String) -> URL {
        guard let url = URL(string: "https://github.com/\(owner)/\(repository)/archive/\(sha).zip") else {
            preconditionFailure("unable to construct GitHub archive URL for \(owner)/\(repository) sha '\(sha)'")
        }
        return url
    }

    public func rawFileURL(for path: String, sha: String) -> URL {
        let escapedPath = path.addingPercentEncoding(withAllowedCharacters: Self.urlPathComponentAllowed) ?? path
        let escapedSHA = sha.addingPercentEncoding(withAllowedCharacters: Self.urlPathComponentAllowed) ?? sha
        guard let url = URL(string: "https://raw.githubusercontent.com/\(owner)/\(repository)/\(escapedSHA)/\(escapedPath)") else {
            preconditionFailure("unable to construct GitHub raw file URL for \(owner)/\(repository) path '\(path)' sha '\(sha)'")
        }
        return url
    }

}

extension GitHubSourceArchiveProvider {
    /// Parses a GitHub HTTPS URL into an (owner, repository) pair.
    ///
    /// Only HTTPS URLs on the github.com host are accepted. SSH URLs (e.g.
    /// `git@github.com:owner/repo.git`) and non-GitHub hosts are rejected.
    /// A trailing `.git` suffix on the repository name is stripped if present.
    static func parseGitHubURL(_ url: SourceControlURL) -> (owner: String, repository: String)? {
        guard let parsed = URL(string: url.absoluteString),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "https",
              let host = parsed.host?.lowercased(),
              host == "github.com"
        else {
            return nil
        }

        let components = parsed.pathComponents.filter { $0 != "/" }
        guard components.count >= 2 else { return nil }

        let owner = components[0]
        var repository = components[1]

        if repository.hasSuffix(".git") {
            repository = String(repository.dropLast(4))
        }

        guard !owner.isEmpty, !repository.isEmpty else { return nil }

        return (owner, repository)
    }
}

// MARK: - GitHub Token Authorization

extension GitHubSourceArchiveProvider {
    /// The set of hostnames that should receive GitHub API tokens.
    private static let gitHubHosts: Set<String> = [
        "github.com", "api.github.com", "raw.githubusercontent.com", "codeload.github.com",
    ]

    /// Fallback URL used to look up credentials for GitHub subdomains.
    private static let gitHubDotComURL = URL(string: "https://github.com/")!

    /// Wraps an existing authorization provider, falling back to
    /// `GITHUB_TOKEN` / `GH_TOKEN` environment variables for GitHub hosts.
    ///
    /// GitHub accepts Basic auth with `token:<pat>` credentials, which is
    /// what the default `httpAuthorizationHeader(for:)` protocol extension
    /// produces from the `(user, password)` tuple returned here. No custom
    /// `httpAuthorizationHeader` override is needed — and adding one would
    /// not work through `any AuthorizationProvider` existentials since the
    /// method is not a protocol requirement.
    public struct GitHubTokenAuthorizationProvider: AuthorizationProvider {
        private let underlying: (any AuthorizationProvider)?

        public init(underlying: (any AuthorizationProvider)?) {
            self.underlying = underlying
        }

        public func authentication(for url: URL) -> (user: String, password: String)? {
            if let auth = underlying?.authentication(for: url) {
                return auth
            }
            guard let host = url.host?.lowercased(),
                  GitHubSourceArchiveProvider.gitHubHosts.contains(host)
            else {
                return nil
            }
            // The underlying provider may only have credentials for github.com,
            // not for subdomains like codeload.github.com or raw.githubusercontent.com.
            // Try github.com as a fallback before checking environment variables.
            if host != "github.com",
               let auth = underlying?.authentication(for: GitHubSourceArchiveProvider.gitHubDotComURL)
            {
                return auth
            }
            if let token = Environment.current["GITHUB_TOKEN"] ?? Environment.current["GH_TOKEN"] {
                return (user: "token", password: token)
            }
            return nil
        }
    }
}
