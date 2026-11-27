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

import Basics
import Foundation
import Testing

struct SourceArchiveProviderTests {

    // MARK: - GitHubSourceArchiveProvider.make(for:) — valid URLs

    struct ValidGitHubURL: Sendable, CustomTestStringConvertible {
        let url: String
        let expectedOwner: String
        let expectedRepository: String
        var testDescription: String { url }
    }

    static let validGitHubURLs: [ValidGitHubURL] = [
        ValidGitHubURL(
            url: "https://github.com/apple/swift-nio.git",
            expectedOwner: "apple",
            expectedRepository: "swift-nio"
        ),
        ValidGitHubURL(
            url: "https://github.com/apple/swift-nio",
            expectedOwner: "apple",
            expectedRepository: "swift-nio"
        ),
        ValidGitHubURL(
            url: "https://github.com/Apple/Swift-NIO.git",
            expectedOwner: "Apple",
            expectedRepository: "Swift-NIO"
        ),
    ]

    @Test("make(for:) returns provider for valid GitHub HTTPS URL", arguments: validGitHubURLs)
    func makeReturnsProvider(input: ValidGitHubURL) {
        let provider = GitHubSourceArchiveProvider.make(for: SourceControlURL(input.url))
        #expect(provider != nil)
        #expect(provider?.owner == input.expectedOwner)
        #expect(provider?.repository == input.expectedRepository)
    }

    // MARK: - GitHubSourceArchiveProvider.make(for:) — rejected URLs

    static let rejectedURLs: [String] = [
        "git@github.com:apple/swift-nio.git",   // SSH
        "https://gitlab.com/foo/bar.git",        // non-GitHub host
        "http://github.com/foo/bar",             // HTTP (not HTTPS)
        "https://github.com/apple",              // too few path components
    ]

    @Test("make(for:) returns nil for unsupported URL", arguments: rejectedURLs)
    func makeReturnsNil(url: String) {
        let provider = GitHubSourceArchiveProvider.make(for: SourceControlURL(url))
        #expect(provider == nil)
    }

    // MARK: - URL construction

    @Test
    func archiveURL() {
        let provider = GitHubSourceArchiveProvider(owner: "apple", repository: "swift-nio")
        let url = provider.archiveURL(forSHA: "bdf004b44f77c56fca752cd1cf243c802f8469c9")
        #expect(url.absoluteString == "https://github.com/apple/swift-nio/archive/bdf004b44f77c56fca752cd1cf243c802f8469c9.zip")
    }

    @Test
    func host() {
        let provider = GitHubSourceArchiveProvider(owner: "apple", repository: "swift-nio")
        #expect(provider.host == "github.com")
    }

    @Test
    func rawFileURL() {
        let provider = GitHubSourceArchiveProvider(owner: "apple", repository: "swift-nio")
        let url = provider.rawFileURL(for: "Package.swift", sha: "abc123")
        #expect(url.absoluteString == "https://raw.githubusercontent.com/apple/swift-nio/abc123/Package.swift")
    }

    // MARK: - GitHubTokenAuthorizationProvider

    @Test
    func gitHubTokenProviderDelegatesWhenUnderlyingHasAuth() {
        let underlying = FixedAuthProvider(user: "netrc-user", password: "netrc-pass")
        let provider = GitHubSourceArchiveProvider.GitHubTokenAuthorizationProvider(underlying: underlying)
        let url = URL(string: "https://github.com/foo/bar")!
        let auth = provider.authentication(for: url)
        #expect(auth?.user == "netrc-user")
        #expect(auth?.password == "netrc-pass")
    }

    @Test
    func gitHubTokenProviderAuthenticatesCodeloadHost() {
        let underlying = FixedAuthProvider(user: "token", password: "ghp_secret")
        let provider = GitHubSourceArchiveProvider.GitHubTokenAuthorizationProvider(underlying: underlying)
        let url = URL(string: "https://codeload.github.com/apple/swift-nio/zip/refs/tags/2.77.0")!
        let auth = provider.authentication(for: url)
        #expect(auth?.user == "token")
        #expect(auth?.password == "ghp_secret")
    }

    @Test
    func gitHubTokenProviderReturnsNilForNonGitHubHost() {
        let provider = GitHubSourceArchiveProvider.GitHubTokenAuthorizationProvider(underlying: nil)
        let url = URL(string: "https://gitlab.com/foo/bar")!
        let auth = provider.authentication(for: url)
        #expect(auth == nil)
    }

    @Test
    func gitHubTokenProviderFallsBackToGitHubDotComForSubdomains() {
        let underlying = GitHubDotComOnlyAuthProvider(user: "netrc-user", password: "netrc-pass")
        let provider = GitHubSourceArchiveProvider.GitHubTokenAuthorizationProvider(underlying: underlying)

        let codeloadURL = URL(string: "https://codeload.github.com/ordo-one/ordo-sdk/zip/refs/tags/1.0.0")!
        let auth = provider.authentication(for: codeloadURL)
        #expect(auth?.user == "netrc-user")
        #expect(auth?.password == "netrc-pass")

        let rawURL = URL(string: "https://raw.githubusercontent.com/ordo-one/ordo-sdk/abc123/Package.swift")!
        let rawAuth = provider.authentication(for: rawURL)
        #expect(rawAuth?.user == "netrc-user")
        #expect(rawAuth?.password == "netrc-pass")
    }

}

private struct FixedAuthProvider: AuthorizationProvider {
    let user: String
    let password: String

    func authentication(for url: URL) -> (user: String, password: String)? {
        (user: user, password: password)
    }
}

private struct GitHubDotComOnlyAuthProvider: AuthorizationProvider {
    let user: String
    let password: String

    func authentication(for url: URL) -> (user: String, password: String)? {
        guard url.host?.lowercased() == "github.com" else { return nil }
        return (user: user, password: password)
    }
}
