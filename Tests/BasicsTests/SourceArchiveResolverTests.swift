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

@testable import Basics
import Foundation
import Testing

import struct TSCUtility.Version

// MARK: - Test Case Types

/// A test case for `hasSubmodules` covering all HTTP response scenarios.
struct HasSubmodulesCase: CustomTestStringConvertible, Sendable {
    let label: String
    let response: HTTPClientResponse
    /// If true, the call is expected to throw `SourceArchiveResolverError`.
    let shouldThrow: Bool
    /// Expected result when the call does not throw.
    let expected: Bool

    var testDescription: String { label }
}

/// A test case for `probeManifestVariant` covering variant resolution scenarios.
struct ProbeManifestVariantCase: CustomTestStringConvertible, Sendable {
    let label: String
    /// The filename that, if requested, should return 200. Nil means all return 404.
    let okFilename: String?
    let expected: String?

    var testDescription: String { label }
}

/// A test case for `fetchManifest` / `fetchManifestFile` covering fetch scenarios.
struct FetchManifestCase: CustomTestStringConvertible, Sendable {
    let label: String
    let response: HTTPClientResponse
    /// If true, the call is expected to throw `SourceArchiveResolverError`.
    let shouldThrow: Bool
    /// Expected string result when the call does not throw.
    let expected: String?
    /// If non-nil, use `fetchManifestFile` with this filename instead of `fetchManifest`.
    let variantFilename: String?

    var testDescription: String { label }
}

// MARK: - Full pipeline (parse → peel → filter)

@Suite("Full pipeline: peeling before filtering")
struct PipelineTests {

    @Test("annotated non-semver tags are peeled then excluded")
    func peelingHappensBeforeFiltering() {
        let output = """
        aaa111aaa111aaa111aaa111aaa111aaa111aaa1\trefs/tags/v1.0.0
        bbb222bbb222bbb222bbb222bbb222bbb222bbb2\trefs/tags/v1.0.0^{}
        abc123abc123abc123abc123abc123abc123abc1\trefs/tags/not-a-version
        def456def456def456def456def456def456def4\trefs/tags/not-a-version^{}
        fff000fff000fff000fff000fff000fff000fff0\trefs/tags/2.0.0
        """
        let rawTags = SourceArchiveResolver.parseLsRemoteOutput(output)
        let peeled = SourceArchiveResolver.peelTags(rawTags)

        #expect(peeled.count == 3)
        #expect(peeled[0].name == "v1.0.0")
        #expect(peeled[0].sha == "bbb222bbb222bbb222bbb222bbb222bbb222bbb2")
        #expect(peeled[1].name == "not-a-version")
        #expect(peeled[1].sha == "def456def456def456def456def456def456def4")
        #expect(peeled[2].name == "2.0.0")
        #expect(peeled[2].sha == "fff000fff000fff000fff000fff000fff000fff0")

        let filtered = SourceArchiveResolver.filterSemverTags(peeled)
        #expect(filtered.count == 2)
        #expect(filtered[0] == ResolvedTag(name: "v1.0.0", sha: "bbb222bbb222bbb222bbb222bbb222bbb222bbb2"))
        #expect(filtered[1] == ResolvedTag(name: "2.0.0", sha: "fff000fff000fff000fff000fff000fff000fff0"))
    }
}

// MARK: - Tag store caching

@Suite("tagStore")
struct TagStoreCachingTests {

    private static let lsRemoteOutput = """
    aaa111\trefs/tags/1.0.0
    bbb222\trefs/tags/2.0.0
    """

    @Test("shared tag memoizer works across resolver instances")
    func tagMemoizerSharedAcrossResolvers() async throws {
        let fetchCount = ThreadSafeBox<Int>(0)
        let tagMemoizer = ThrowingAsyncKeyValueMemoizer<String, [ResolvedTag]>()

        let makeResolver = {
            SourceArchiveResolver(
                httpClient: HTTPClient { _, _ in .notFound() },
                gitTagsProvider: { _ in
                    fetchCount.mutate { $0 += 1 }
                    return Self.lsRemoteOutput
                },
                tagMemoizer: tagMemoizer
            )
        }

        let url = SourceControlURL("https://github.com/test/repo.git")
        _ = try await makeResolver().getTags(for: url)
        _ = try await makeResolver().getTags(for: url)

        #expect(fetchCount.get() == 1)
    }
}

// MARK: - Mock Provider for HTTP-level tests

/// A simple mock ``SourceArchiveProvider`` that constructs predictable URLs.
private struct MockSourceArchiveProvider: SourceArchiveProvider {
    let owner: String
    let repo: String

    var host: String { "example.com" }
    var cacheKey: (owner: String, repo: String) { (owner, repo) }

    func archiveURL(forSHA sha: String) -> URL {
        URL(string: "https://example.com/\(owner)/\(repo)/archive/\(sha).zip")!
    }

    func rawFileURL(for path: String, sha: String) -> URL {
        URL(string: "https://example.com/\(owner)/\(repo)/raw/\(sha)/\(path)")!
    }
}

// MARK: - hasSubmodules

@Suite("hasSubmodules")
struct HasSubmodulesTests {

    private static let provider = MockSourceArchiveProvider(owner: "test", repo: "repo")
    private static let sha = "abc123"

    static let cases: [HasSubmodulesCase] = [
        HasSubmodulesCase(
            label: "200 with [submodule in body returns true",
            response: .okay(body: "[submodule \"Vendor/Lib\"]\n  path = Vendor/Lib\n  url = https://example.com/lib.git"),
            shouldThrow: false,
            expected: true
        ),
        HasSubmodulesCase(
            label: "200 with empty body returns false",
            response: .okay(body: Data()),
            shouldThrow: false,
            expected: false
        ),
        HasSubmodulesCase(
            label: "200 with body not containing [submodule returns false",
            response: .okay(body: "# This file is empty of submodule entries"),
            shouldThrow: false,
            expected: false
        ),
        HasSubmodulesCase(
            label: "404 returns false",
            response: .notFound(),
            shouldThrow: false,
            expected: false
        ),
        HasSubmodulesCase(
            label: "server error throws unexpectedHTTPStatus",
            response: .serverError(),
            shouldThrow: true,
            expected: false
        ),
    ]

    @Test("checks submodule presence correctly", arguments: cases)
    func hasSubmodules(testCase: HasSubmodulesCase) async throws {
        let httpClient = HTTPClient { _, _ in testCase.response }
        let resolver = SourceArchiveResolver(httpClient: httpClient)

        if testCase.shouldThrow {
            await #expect(throws: SourceArchiveResolverError.self) {
                try await resolver.hasSubmodules(provider: Self.provider, sha: Self.sha)
            }
        } else {
            let result = try await resolver.hasSubmodules(provider: Self.provider, sha: Self.sha)
            #expect(result == testCase.expected)
        }
    }
}

// MARK: - probeManifestVariant

@Suite("probeManifestVariant")
struct ProbeManifestVariantTests {

    private static let provider = MockSourceArchiveProvider(owner: "test", repo: "repo")
    private static let sha = "def456"

    static let cases: [ProbeManifestVariantCase] = [
        ProbeManifestVariantCase(
            label: "returns full X.Y.Z variant when HEAD returns 200",
            okFilename: "Package@swift-5.9.2.swift",
            expected: "Package@swift-5.9.2.swift"
        ),
        ProbeManifestVariantCase(
            label: "returns X.Y variant when X.Y.Z is 404 but X.Y is 200",
            okFilename: "Package@swift-5.9.swift",
            expected: "Package@swift-5.9.swift"
        ),
        ProbeManifestVariantCase(
            label: "returns X variant when X.Y.Z and X.Y are 404 but X is 200",
            okFilename: "Package@swift-5.swift",
            expected: "Package@swift-5.swift"
        ),
        ProbeManifestVariantCase(
            label: "returns nil when all candidates return 404",
            okFilename: nil,
            expected: nil
        ),
    ]

    @Test("probes manifest variant correctly", arguments: cases)
    func probeManifestVariant(testCase: ProbeManifestVariantCase) async throws {
        let httpClient = HTTPClient { request, _ in
            if let okFilename = testCase.okFilename,
               request.url.lastPathComponent == okFilename {
                return .okay()
            }
            return .notFound()
        }
        let resolver = SourceArchiveResolver(httpClient: httpClient)
        let result = try await resolver.probeManifestVariant(
            provider: Self.provider,
            sha: Self.sha,
            swiftVersion: .init(5, 9, 2)
        )
        #expect(result == testCase.expected)
    }
}

// MARK: - fetchManifest / fetchManifestFile

@Suite("fetchManifest and fetchManifestFile")
struct FetchManifestTests {

    private static let provider = MockSourceArchiveProvider(owner: "test", repo: "repo")
    private static let sha = "aabbcc"

    static let cases: [FetchManifestCase] = [
        FetchManifestCase(
            label: "200 with valid body returns content",
            response: .okay(body: "// swift-tools-version: 5.9\nimport PackageDescription\n"),
            shouldThrow: false,
            expected: "// swift-tools-version: 5.9\nimport PackageDescription\n",
            variantFilename: nil
        ),
        FetchManifestCase(
            label: "404 throws manifestNotFound",
            response: .notFound(),
            shouldThrow: true,
            expected: nil,
            variantFilename: nil
        ),
        FetchManifestCase(
            label: "200 with nil body throws manifestNotFound",
            response: HTTPClientResponse(statusCode: 200, body: nil),
            shouldThrow: true,
            expected: nil,
            variantFilename: nil
        ),
        FetchManifestCase(
            label: "fetchManifestFile with specific filename succeeds",
            response: .okay(body: "// swift-tools-version: 5.9\n"),
            shouldThrow: false,
            expected: "// swift-tools-version: 5.9\n",
            variantFilename: "Package@swift-5.9.swift"
        ),
    ]

    @Test("fetches manifest correctly", arguments: cases)
    func fetchManifest(testCase: FetchManifestCase) async throws {
        let httpClient = HTTPClient { _, _ in testCase.response }
        let resolver = SourceArchiveResolver(httpClient: httpClient)

        if testCase.shouldThrow {
            await #expect(throws: SourceArchiveResolverError.self) {
                if let filename = testCase.variantFilename {
                    _ = try await resolver.fetchManifestFile(
                        provider: Self.provider, sha: Self.sha, filename: filename)
                } else {
                    _ = try await resolver.fetchManifest(provider: Self.provider, sha: Self.sha)
                }
            }
        } else {
            let result: String
            if let filename = testCase.variantFilename {
                result = try await resolver.fetchManifestFile(
                    provider: Self.provider, sha: Self.sha, filename: filename)
            } else {
                result = try await resolver.fetchManifest(provider: Self.provider, sha: Self.sha)
            }
            #expect(result == testCase.expected)
        }
    }
}

// MARK: - authHeaders

/// A mock authorization provider that returns a fixed header value.
private struct MockAuthorizationProvider: AuthorizationProvider {
    let isAuthenticated: Bool

    func authentication(for url: URL) -> (user: String, password: String)? {
        guard isAuthenticated else { return nil }
        return (user: "token", password: "secret")
    }
}

@Suite("authHeaders")
struct AuthHeadersTests {

    private static let provider = MockSourceArchiveProvider(owner: "test", repo: "repo")
    private static let sha = "abc123"

    @Test("no auth provider produces no Authorization header")
    func noAuth() async throws {
        let capturedHeaders = ThreadSafeBox<HTTPClientHeaders>(HTTPClientHeaders())
        let httpClient = HTTPClient { request, _ in
            capturedHeaders.mutate { $0 = request.headers }
            return .okay(body: "content")
        }
        let resolver = SourceArchiveResolver(httpClient: httpClient)
        _ = try await resolver.fetchManifest(provider: Self.provider, sha: Self.sha)
        let authValues = capturedHeaders.get().get("Authorization")
        #expect(authValues.isEmpty)
    }

    @Test("auth provider returns value which is used in request headers")
    func withAuthProvider() async throws {
        let capturedHeaders = ThreadSafeBox<HTTPClientHeaders>(HTTPClientHeaders())
        let httpClient = HTTPClient { request, _ in
            capturedHeaders.mutate { $0 = request.headers }
            return .okay(body: "content")
        }
        let authProvider = MockAuthorizationProvider(isAuthenticated: true)
        let resolver = SourceArchiveResolver(httpClient: httpClient, authorizationProvider: authProvider)
        _ = try await resolver.fetchManifest(provider: Self.provider, sha: Self.sha)
        let authValues = capturedHeaders.get().get("Authorization")
        #expect(!authValues.isEmpty)
    }
}

// MARK: - probeManifestVariant error propagation

@Suite("probeManifestVariant error propagation")
struct ProbeManifestVariantErrorTests {

    private static let provider = MockSourceArchiveProvider(owner: "test", repo: "repo")
    private static let sha = "def456"

    struct ErrorStatusCase: CustomTestStringConvertible, Sendable {
        let label: String
        let statusCode: Int

        var testDescription: String { label }
    }

    static let errorStatusCases: [ErrorStatusCase] = [
        ErrorStatusCase(label: "401 Unauthorized", statusCode: 401),
        ErrorStatusCase(label: "403 Forbidden", statusCode: 403),
        ErrorStatusCase(label: "500 Internal Server Error", statusCode: 500),
    ]

    @Test("non-404 error status codes propagate as unexpectedHTTPStatus", arguments: errorStatusCases)
    func errorStatusCodePropagates(testCase: ErrorStatusCase) async throws {
        let httpClient = HTTPClient { _, _ in
            HTTPClientResponse(statusCode: testCase.statusCode)
        }
        let resolver = SourceArchiveResolver(httpClient: httpClient)
        await #expect(throws: SourceArchiveResolverError.self) {
            try await resolver.probeManifestVariant(
                provider: Self.provider,
                sha: Self.sha,
                swiftVersion: .init(5, 9, 2)
            )
        }
    }

    @Test("transport error propagates instead of returning nil")
    func transportErrorPropagates() async throws {
        let httpClient = HTTPClient { _, _ in
            throw StringError("connection refused")
        }
        let resolver = SourceArchiveResolver(httpClient: httpClient)
        await #expect(throws: (any Error).self) {
            try await resolver.probeManifestVariant(
                provider: Self.provider,
                sha: Self.sha,
                swiftVersion: .init(5, 9, 2)
            )
        }
    }
}

// MARK: - Non-UTF8 encoding tests

@Suite("Non-UTF8 encoding handling")
struct NonUTF8EncodingTests {

    private static let provider = MockSourceArchiveProvider(owner: "test", repo: "repo")
    private static let sha = "abc123"

    @Test("fetchManifest with 200 response but non-UTF8 body throws invalidManifestEncoding")
    func fetchManifestNonUTF8BodyThrowsInvalidEncoding() async throws {
        let invalidUTF8 = Data([0xFF, 0xFE])
        let httpClient = HTTPClient { request, _ in
            .okay(body: invalidUTF8)
        }
        let resolver = SourceArchiveResolver(httpClient: httpClient)
        await #expect(throws: SourceArchiveResolverError.self) {
            try await resolver.fetchManifest(provider: Self.provider, sha: Self.sha)
        }
    }

    @Test("hasSubmodules with 200 response but non-UTF8 body returns false")
    func hasSubmodulesNonUTF8BodyReturnsFalse() async throws {
        let invalidUTF8 = Data([0xFF, 0xFE])
        let httpClient = HTTPClient { request, _ in
            .okay(body: invalidUTF8)
        }
        let resolver = SourceArchiveResolver(httpClient: httpClient)
        let result = try await resolver.hasSubmodules(provider: Self.provider, sha: Self.sha)
        #expect(result == false)
    }
}

