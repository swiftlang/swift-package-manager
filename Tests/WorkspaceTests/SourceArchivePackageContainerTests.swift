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
import _InternalTestSupport
import PackageGraph
import PackageLoading
import PackageModel
@testable import Workspace
import Testing

import struct TSCUtility.Version

/// Tests for ``SourceArchivePackageContainer``.
@Suite
private struct SourceArchivePackageContainerTests {

    // MARK: - Helpers

    /// A minimal mock ``SourceArchiveProvider`` for testing.
    private struct MockProvider: SourceArchiveProvider {
        let owner: String
        let repo: String

        var host: String { "example.com" }
        var cacheKey: (owner: String, repo: String) { (owner, repo) }

        func archiveURL(forSHA sha: String) -> URL {
            URL(string: "https://example.com/\(owner)/\(repo)/archive/\(sha).zip")!
        }

        func rawFileURL(for path: String, sha: String) -> URL {
            URL(string: "https://raw.example.com/\(owner)/\(repo)/\(sha)/\(path)")!
        }
    }

    private static let defaultManifest =
        "// swift-tools-version:5.9\nimport PackageDescription\nlet package = Package(name: \"Foo\")\n"

    /// Creates a pre-configured ``SourceArchiveMetadataCache`` backed by an in-memory filesystem.
    private static func makeMetadataCache(
        fileSystem fs: InMemoryFileSystem = InMemoryFileSystem()
    ) throws -> (cache: SourceArchiveMetadataCache, fileSystem: InMemoryFileSystem) {
        let cachePath = AbsolutePath("/tmp/test-cache")
        try fs.createDirectory(cachePath, recursive: true)
        return (SourceArchiveMetadataCache(fileSystem: fs, cachePath: cachePath), fs)
    }

    /// Creates a container with the given configuration, optionally injecting pre-resolved tags.
    ///
    /// Pass a custom `httpClient` to intercept or track HTTP requests (e.g. for
    /// verifying caching behaviour). When `nil`, a default client is built from
    /// `manifestContentBySHA` and `headResponses`.
    private static func makeContainer(
        packageURL: String = "https://github.com/owner/repo.git",
        tags: [ResolvedTag]? = nil,
        manifestContentBySHA: [String: String] = [:],
        manifestsByVersion: [MockManifestLoader.Key: Manifest] = [:],
        headResponses: [String: Int] = [:],
        httpClient: HTTPClient? = nil,
        provider: MockProvider? = nil,
        metadataCache: SourceArchiveMetadataCache? = nil,
        currentToolsVersion: ToolsVersion = .current,
        observabilityScope: ObservabilityScope? = nil
    ) async throws -> SourceArchivePackageContainer {
        let url = SourceControlURL(stringLiteral: packageURL)
        let identity = PackageIdentity(url: url)
        let packageRef = PackageReference(
            identity: identity,
            kind: .remoteSourceControl(url)
        )

        let resolvedHTTPClient = httpClient ?? HTTPClient(implementation: { request, _ in
            let urlString = request.url.absoluteString

            if request.method == .head {
                if let statusCode = headResponses[urlString] {
                    return HTTPClientResponse(statusCode: statusCode)
                }
                return .notFound()
            }

            for (sha, content) in manifestContentBySHA {
                if urlString.contains("/\(sha)/") {
                    return .okay(body: content)
                }
            }

            return .notFound()
        })

        let resolver = SourceArchiveResolver(
            httpClient: resolvedHTTPClient,
            authorizationProvider: nil
        )

        let resolvedCache: SourceArchiveMetadataCache
        if let metadataCache {
            resolvedCache = metadataCache
        } else {
            let fs = InMemoryFileSystem()
            let cachePath = AbsolutePath("/tmp/test-cache")
            try fs.createDirectory(cachePath, recursive: true)
            resolvedCache = SourceArchiveMetadataCache(fileSystem: fs, cachePath: cachePath)
        }

        let container = SourceArchivePackageContainer(
            package: packageRef,
            provider: provider ?? MockProvider(owner: "owner", repo: "repo"),
            resolver: resolver,
            metadataCache: resolvedCache,
            manifestLoader: MockManifestLoader(manifests: manifestsByVersion),
            identityResolver: DefaultIdentityResolver(),
            dependencyMapper: DefaultDependencyMapper(identityResolver: DefaultIdentityResolver()),
            currentToolsVersion: currentToolsVersion,
            observabilityScope: observabilityScope ?? ObservabilitySystem.makeForTesting().topScope
        )

        if let tags {
            try await container.injectResolvedTags(tags)
        }

        return container
    }

    // MARK: - Container tests

    @Test("toolsVersion caches result for repeated calls")
    func toolsVersionCaching() async throws {
        let fetchCount = ThreadSafeBox<Int>(0)

        let httpClient = HTTPClient(implementation: { request, _ in
            if request.method == .head { return .notFound() }
            if request.url.absoluteString.contains("/aaa111/Package.swift") {
                fetchCount.mutate { $0 += 1 }
                return .okay(body: Self.defaultManifest)
            }
            return .notFound()
        })

        let container = try await Self.makeContainer(
            tags: [ResolvedTag(name: "1.0.0", commitSHA: "aaa111", version: Version(1, 0, 0))],
            httpClient: httpClient
        )

        let tv1 = try await container.toolsVersion(for: Version(1, 0, 0))
        let tv2 = try await container.toolsVersion(for: Version(1, 0, 0))
        #expect(tv1 == tv2)
        #expect(fetchCount.get() == 1)
    }

    // MARK: - toolsVersionsAppropriateVersionsDescending

    /// 4 package versions, each requiring a different minimum tools version.
    private static let versionToolsVersionTags: [ResolvedTag] = [
        ResolvedTag(name: "1.0.0", commitSHA: "sha_v3", version: Version(1, 0, 0)),
        ResolvedTag(name: "1.0.1", commitSHA: "sha_v4", version: Version(1, 0, 1)),
        ResolvedTag(name: "1.0.2", commitSHA: "sha_v5_4", version: Version(1, 0, 2)),
        ResolvedTag(name: "1.0.3", commitSHA: "sha_v5_9", version: Version(1, 0, 3)),
    ]

    private static let versionToolsVersionManifests: [String: String] = [
        "sha_v3": "// swift-tools-version:3.1\nimport PackageDescription\nlet package = Package(name: \"Foo\")\n",
        "sha_v4": "// swift-tools-version:4.0\nimport PackageDescription\nlet package = Package(name: \"Foo\")\n",
        "sha_v5_4": "// swift-tools-version:5.4\nimport PackageDescription\nlet package = Package(name: \"Foo\")\n",
        "sha_v5_9": "// swift-tools-version:5.9\nimport PackageDescription\nlet package = Package(name: \"Foo\")\n",
    ]

    struct ToolsVersionCompatCase: CustomTestStringConvertible {
        let currentToolsVersion: ToolsVersion
        let expectedVersions: [Version]
        var testDescription: String { "toolchain \(currentToolsVersion) → \(expectedVersions)" }
    }

    static let toolsVersionCompatCases: [ToolsVersionCompatCase] = [
        // v4.0 toolchain: can only use packages requiring ≤ v4.0
        ToolsVersionCompatCase(
            currentToolsVersion: .v4,
            expectedVersions: [Version(1, 0, 1)]
        ),
        // v5.4 toolchain: can use v4.0 and v5.4
        ToolsVersionCompatCase(
            currentToolsVersion: .v5_4,
            expectedVersions: [Version(1, 0, 2), Version(1, 0, 1)]
        ),
        // v5.9 toolchain: can use v4.0, v5.4, and v5.9
        ToolsVersionCompatCase(
            currentToolsVersion: .v5_9,
            expectedVersions: [Version(1, 0, 3), Version(1, 0, 2), Version(1, 0, 1)]
        ),
    ]

    @Test("toolsVersionsAppropriateVersionsDescending across toolchain versions", arguments: toolsVersionCompatCases)
    func toolsVersionsAppropriateVersionsDescending(testCase: ToolsVersionCompatCase) async throws {
        let container = try await Self.makeContainer(
            tags: Self.versionToolsVersionTags,
            manifestContentBySHA: Self.versionToolsVersionManifests,
            currentToolsVersion: testCase.currentToolsVersion
        )

        let appropriate = try await container.toolsVersionsAppropriateVersionsDescending()
        #expect(appropriate == testCase.expectedVersions)
    }

    // MARK: - getTag / getRevision (parameterized)

    enum TagRevisionLookup: CustomTestStringConvertible {
        case getTagKnown(version: Version, expectedTag: String)
        case getTagUnknown(version: Version)
        case getRevisionKnown(tag: String, expectedSHA: String)
        case getRevisionUnknown(tag: String)

        var testDescription: String {
            switch self {
            case .getTagKnown(let v, let t): return "getTag(\(v)) -> \(t)"
            case .getTagUnknown(let v): return "getTag(\(v)) -> nil"
            case .getRevisionKnown(let t, let sha): return "getRevision(\(t)) -> \(sha)"
            case .getRevisionUnknown(let t): return "getRevision(\(t)) -> throws"
            }
        }
    }

    struct TagRevisionCase: CustomTestStringConvertible {
        let lookup: TagRevisionLookup
        var testDescription: String { lookup.testDescription }
    }

    static let tagRevisionCases: [TagRevisionCase] = [
        TagRevisionCase(lookup: .getTagKnown(version: Version(1, 0, 0), expectedTag: "1.0.0")),
        TagRevisionCase(lookup: .getTagKnown(version: Version(2, 0, 0), expectedTag: "v2.0.0")),
        TagRevisionCase(lookup: .getTagUnknown(version: Version(9, 9, 9))),
        TagRevisionCase(lookup: .getRevisionKnown(tag: "1.0.0", expectedSHA: "sha100")),
        TagRevisionCase(lookup: .getRevisionKnown(tag: "v2.0.0", expectedSHA: "sha200")),
        TagRevisionCase(lookup: .getRevisionUnknown(tag: "nonexistent")),
    ]

    @Test("getTag and getRevision return correct results including duplicate-version preference", arguments: tagRevisionCases)
    func tagRevisionLookup(testCase: TagRevisionCase) async throws {
        // Includes duplicate tags for the same version (1.0.0 + v1.0.0)
        // to verify the more-specific (non-v-prefixed) tag wins.
        let container = try await Self.makeContainer(
            tags: [
                ResolvedTag(name: "1.0.0", commitSHA: "sha100", version: Version(1, 0, 0)),
                ResolvedTag(name: "v1.0.0", commitSHA: "sha100v", version: Version(1, 0, 0)),
                ResolvedTag(name: "v2.0.0", commitSHA: "sha200", version: Version(2, 0, 0)),
            ]
        )

        switch testCase.lookup {
        case .getTagKnown(let version, let expectedTag):
            let tag = try await container.getTag(for: version)
            #expect(tag == expectedTag)
        case .getTagUnknown(let version):
            let tag = try await container.getTag(for: version)
            #expect(tag == nil)
        case .getRevisionKnown(let tag, let expectedSHA):
            let sha = try await container.getRevision(forTag: tag)
            #expect(sha == expectedSHA)
        case .getRevisionUnknown(let tag):
            await #expect(throws: (any Error).self) {
                try await container.getRevision(forTag: tag)
            }
        }
    }

    // MARK: - getDependencies(at version:)

    @Test("getDependencies at version returns manifest dependency constraints")
    func getDependenciesAtVersion() async throws {
        let packageURL = "https://github.com/owner/repo.git"
        let pkgURL = SourceControlURL(stringLiteral: packageURL)
        let pkgIdentity = PackageIdentity(url: pkgURL)
        let depURL = SourceControlURL(stringLiteral: "https://github.com/dep/bar.git")
        let depIdentity = PackageIdentity(url: depURL)

        let manifestObj = Manifest.createManifest(
            displayName: "Foo",
            path: .root.appending(component: "Package.swift"),
            packageKind: .remoteSourceControl(pkgURL),
            packageIdentity: pkgIdentity,
            packageLocation: packageURL,
            toolsVersion: .v5_9,
            dependencies: [
                .remoteSourceControl(
                    identity: depIdentity,
                    nameForTargetDependencyResolutionOnly: nil,
                    url: depURL,
                    requirement: .range(Version(1, 0, 0) ..< Version(2, 0, 0)),
                    productFilter: .everything
                )
            ],
            products: [
                try ProductDescription(name: "FooLib", type: .library(.automatic), targets: ["FooLib"])
            ],
            targets: [
                try TargetDescription(
                    name: "FooLib",
                    dependencies: [.product(name: "Bar", package: "bar")]
                )
            ]
        )

        let key = MockManifestLoader.Key(url: packageURL, version: Version(1, 0, 0))
        let container = try await Self.makeContainer(
            tags: [ResolvedTag(name: "1.0.0", commitSHA: "aaa111", version: Version(1, 0, 0))],
            manifestContentBySHA: ["aaa111": Self.defaultManifest],
            manifestsByVersion: [key: manifestObj]
        )

        let deps = try await container.getDependencies(at: Version(1, 0, 0), productFilter: .everything)
        let dep = try #require(deps.first)
        #expect(dep.package.identity == depIdentity)
    }

    @Test("getDependencies at revision throws without git fallback")
    func getDependenciesAtRevisionThrowsWithoutFallback() async throws {
        let container = try await Self.makeContainer(tags: [])
        await #expect(throws: (any Error).self) {
            try await container.getDependencies(at: "some-revision", productFilter: .everything)
        }
    }

    @Test("getUnversionedDependencies throws without git fallback")
    func getUnversionedDependenciesThrowsWithoutFallback() async throws {
        let container = try await Self.makeContainer(tags: [])
        await #expect(throws: (any Error).self) {
            try await container.getUnversionedDependencies(productFilter: .everything)
        }
    }

    @Test("getDependencies at revision delegates to memoized git fallback")
    func getDependenciesAtRevisionDelegatesToGit() async throws {
        let providerCallCount = ThreadSafeBox<Int>(0)

        let container = try await Self.makeContainer(tags: [])

        // Create a container with a git fallback that tracks how many
        // times the provider closure is invoked (should be exactly once).
        let url = SourceControlURL(stringLiteral: "https://github.com/owner/repo.git")
        let identity = PackageIdentity(url: url)
        let packageRef = PackageReference(identity: identity, kind: .remoteSourceControl(url))
        let httpClient = HTTPClient(implementation: { _, _ in .notFound() })
        let resolver = SourceArchiveResolver(httpClient: httpClient)
        let fs = InMemoryFileSystem()
        let cachePath = AbsolutePath("/tmp/test-git-fallback")
        try fs.createDirectory(cachePath, recursive: true)

        let containerWithFallback = SourceArchivePackageContainer(
            package: packageRef,
            provider: MockProvider(owner: "owner", repo: "repo"),
            resolver: resolver,
            metadataCache: SourceArchiveMetadataCache(fileSystem: fs, cachePath: cachePath),
            manifestLoader: MockManifestLoader(manifests: [:]),
            identityResolver: DefaultIdentityResolver(),
            dependencyMapper: DefaultDependencyMapper(identityResolver: DefaultIdentityResolver()),
            currentToolsVersion: .current,
            observabilityScope: ObservabilitySystem.makeForTesting().topScope,
            gitContainerProvider: {
                providerCallCount.mutate { $0 += 1 }
                // Return the basic container as a stand-in — it will throw
                // for revision queries too, but the point is verifying the
                // provider is called exactly once (memoized).
                return container
            }
        )

        // First call invokes the provider.
        await #expect(throws: (any Error).self) {
            try await containerWithFallback.getDependencies(at: "main", productFilter: .everything)
        }
        #expect(providerCallCount.get() == 1)

        // Second call reuses the memoized container — provider not called again.
        await #expect(throws: (any Error).self) {
            try await containerWithFallback.getDependencies(at: "develop", productFilter: .everything)
        }
        #expect(providerCallCount.get() == 1)
    }

    // MARK: - loadPackageReference (parameterized)

    @Test("loadPackageReference at version returns reference with manifest display name")
    func loadPackageReferenceAtVersion() async throws {
        let manifest = "// swift-tools-version:5.9\nimport PackageDescription\nlet package = Package(name: \"MyPackage\")\n"
        let packageURL = "https://github.com/owner/repo.git"
        let pkgURL = SourceControlURL(stringLiteral: packageURL)
        let pkgIdentity = PackageIdentity(url: pkgURL)

        let manifestObj = Manifest.createManifest(
            displayName: "MyPackage",
            path: .root.appending(component: "Package.swift"),
            packageKind: .remoteSourceControl(pkgURL),
            packageIdentity: pkgIdentity,
            packageLocation: packageURL,
            toolsVersion: .v5_9
        )

        let key = MockManifestLoader.Key(url: packageURL, version: Version(1, 0, 0))
        let container = try await Self.makeContainer(
            tags: [ResolvedTag(name: "1.0.0", commitSHA: "aaa111", version: Version(1, 0, 0))],
            manifestContentBySHA: ["aaa111": Self.defaultManifest],
            manifestsByVersion: [key: manifestObj]
        )

        let ref = try await container.loadPackageReference(at: .version(Version(1, 0, 0)))
        #expect(ref.deprecatedName == "MyPackage")
    }

    // MARK: - Manifest variant probing

    @Test("fetchManifestContent uses variant when HEAD responds 200")
    func fetchManifestContentUsesVariant() async throws {
        // Base declares 5.8 tools version; variant declares 5.9.
        // If the variant is correctly selected, toolsVersion returns 5.9.
        // If variant selection is broken and the base is used, it returns 5.8.
        let baseManifest = "// swift-tools-version:5.8\nimport PackageDescription\nlet package = Package(name: \"Base\")\n"
        let variantManifest = "// swift-tools-version:5.9\nimport PackageDescription\nlet package = Package(name: \"Variant\")\n"
        let tv = ToolsVersion.current
        let variantFilename = "Package@swift-\(tv.major).\(tv.minor).\(tv.patch).swift"

        let httpClient = HTTPClient(implementation: { request, _ in
            let urlString = request.url.absoluteString
            if request.method == .head {
                return urlString.contains(variantFilename)
                    ? HTTPClientResponse(statusCode: 200)
                    : .notFound()
            }
            if urlString.contains(variantFilename) { return .okay(body: variantManifest) }
            if urlString.contains("Package.swift") { return .okay(body: baseManifest) }
            return .notFound()
        })

        let packageURL = "https://github.com/owner/repo.git"
        let pkgURL = SourceControlURL(stringLiteral: packageURL)
        let manifestObj = Manifest.createManifest(
            displayName: "Variant",
            path: .root.appending(component: "Package.swift"),
            packageKind: .remoteSourceControl(pkgURL),
            packageIdentity: PackageIdentity(url: pkgURL),
            packageLocation: packageURL,
            toolsVersion: .v5_9
        )
        let key = MockManifestLoader.Key(url: packageURL, version: Version(1, 0, 0))

        let container = try await Self.makeContainer(
            tags: [ResolvedTag(name: "1.0.0", commitSHA: "aaa111", version: Version(1, 0, 0))],
            manifestsByVersion: [key: manifestObj],
            httpClient: httpClient
        )

        let resolvedTV = try await container.toolsVersion(for: Version(1, 0, 0))
        // 5.9 proves the variant was selected, not the base (which is 5.8).
        #expect(resolvedTV == ToolsVersion(version: "5.9.0"))
    }

    struct VariantProbeErrorCase: CustomTestStringConvertible {
        let statusCode: Int

        var testDescription: String { "variant probe HTTP \(statusCode) propagates" }
    }

    static let variantProbeErrorCases: [VariantProbeErrorCase] = [
        .init(statusCode: 401),
        .init(statusCode: 403),
        .init(statusCode: 500),
    ]

    @Test("toolsVersion does not fall back to base manifest when variant probe errors", arguments: variantProbeErrorCases)
    func variantProbeErrorsPropagate(testCase: VariantProbeErrorCase) async throws {
        let baseManifest = "// swift-tools-version:5.8\nimport PackageDescription\nlet package = Package(name: \"Base\")\n"
        let tv = ToolsVersion.current
        let variantFilename = "Package@swift-\(tv.major).\(tv.minor).\(tv.patch).swift"

        let httpClient = HTTPClient(implementation: { request, _ in
            let urlString = request.url.absoluteString
            if request.method == .head, urlString.contains(variantFilename) {
                return HTTPClientResponse(statusCode: testCase.statusCode)
            }
            if request.method == .head {
                return .notFound()
            }
            if urlString.contains("Package.swift") {
                return .okay(body: baseManifest)
            }
            return .notFound()
        })

        let container = try await Self.makeContainer(
            tags: [ResolvedTag(name: "1.0.0", commitSHA: "aaa111", version: Version(1, 0, 0))],
            httpClient: httpClient
        )

        await #expect(throws: SourceArchiveResolverError.self) {
            _ = try await container.toolsVersion(for: Version(1, 0, 0))
        }
    }

    // MARK: - Manifest variant disk cache hit

    @Test("toolsVersion returns cached variant manifest without any HTTP GET")
    func variantDiskCacheHit() async throws {
        let tv = ToolsVersion.current
        let variantFilename = "Package@swift-\(tv.major).\(tv.minor).\(tv.patch).swift"

        let httpClient = HTTPClient(implementation: { request, _ in
            if request.method == .head {
                return request.url.absoluteString.contains(variantFilename)
                    ? HTTPClientResponse(statusCode: 200)
                    : .notFound()
            }
            Issue.record("unexpected HTTP GET: \(request.url)")
            return .notFound()
        })

        let (cache, _) = try Self.makeMetadataCache()
        try cache.setManifest(
            owner: "owner", repo: "repo", sha: "aaa111",
            filename: variantFilename, content: Self.defaultManifest
        )

        let container = try await Self.makeContainer(
            tags: [ResolvedTag(name: "1.0.0", commitSHA: "aaa111", version: Version(1, 0, 0))],
            httpClient: httpClient,
            metadataCache: cache
        )

        let resolvedTV = try await container.toolsVersion(for: Version(1, 0, 0))
        #expect(resolvedTV == ToolsVersion(version: "5.9.0"))
    }

    // MARK: - hasSubmodules metadata cache hit

    @Test("hasSubmodules returns cached value from metadata cache without HTTP call")
    func hasSubmodulesCacheHit() async throws {
        let httpClient = HTTPClient(implementation: { request, _ in
            if request.url.absoluteString.contains(".gitmodules") {
                Issue.record("unexpected .gitmodules HTTP call — cache should have been used")
            }
            return .notFound()
        })

        // Cache says hasSubmodules=true. If cache is missed, HTTP returns 404
        // which means hasSubmodules=false — so `result == true` proves the cache hit.
        let (cache, _) = try Self.makeMetadataCache()
        try cache.setMetadata(
            owner: "owner", repo: "repo", sha: "aaa111",
            metadata: SourceArchiveMetadata(hasSubmodules: true)
        )

        let container = try await Self.makeContainer(
            tags: [ResolvedTag(name: "1.0.0", commitSHA: "aaa111", version: Version(1, 0, 0))],
            httpClient: httpClient,
            metadataCache: cache
        )

        let result = try await container.hasSubmodules(at: Version(1, 0, 0))
        #expect(result == true)
    }

    // MARK: - Manifest cache: different versions on same commit

    @Test("loadManifest returns distinct manifests for different versions sharing the same SHA")
    func manifestCacheDistinguishesByVersion() async throws {
        let packageURL = "https://github.com/owner/repo.git"
        let pkgURL = SourceControlURL(stringLiteral: packageURL)
        let pkgIdentity = PackageIdentity(url: pkgURL)

        // Two versions point to the same commit SHA.
        let manifestV1 = Manifest.createManifest(
            displayName: "Foo",
            path: .root.appending(component: "Package.swift"),
            packageKind: .remoteSourceControl(pkgURL),
            packageIdentity: pkgIdentity,
            packageLocation: packageURL,
            toolsVersion: .v5_9
        )
        let manifestV2 = Manifest.createManifest(
            displayName: "Foo",
            path: .root.appending(component: "Package.swift"),
            packageKind: .remoteSourceControl(pkgURL),
            packageIdentity: pkgIdentity,
            packageLocation: packageURL,
            toolsVersion: .v5_9
        )

        let key1 = MockManifestLoader.Key(url: packageURL, version: Version(1, 0, 0))
        let key2 = MockManifestLoader.Key(url: packageURL, version: Version(2, 0, 0))

        let container = try await Self.makeContainer(
            tags: [
                ResolvedTag(name: "1.0.0", commitSHA: "same-sha", version: Version(1, 0, 0)),
                ResolvedTag(name: "2.0.0", commitSHA: "same-sha", version: Version(2, 0, 0)),
            ],
            manifestContentBySHA: ["same-sha": Self.defaultManifest],
            manifestsByVersion: [key1: manifestV1, key2: manifestV2]
        )

        // Load dependencies for both versions — both resolve to "same-sha"
        // but should get distinct Manifest objects with correct versions.
        let deps1 = try await container.getDependencies(at: Version(1, 0, 0), productFilter: .everything)
        let deps2 = try await container.getDependencies(at: Version(2, 0, 0), productFilter: .everything)

        // Both are empty (no deps declared) — the key point is neither call
        // throws or returns stale data from the other version's cache entry.
        #expect(deps1.isEmpty)
        #expect(deps2.isEmpty)

        // Verify loadPackageReference returns correctly for both versions.
        let ref1 = try await container.loadPackageReference(at: .version(Version(1, 0, 0)))
        let ref2 = try await container.loadPackageReference(at: .version(Version(2, 0, 0)))
        #expect(ref1.deprecatedName == "Foo")
        #expect(ref2.deprecatedName == "Foo")
    }

    // MARK: - prefetchManifestContents disk cache skip

    @Test("prefetchManifestContents skips HTTP for SHAs already in disk cache")
    func prefetchSkipsDiskCacheHits() async throws {
        let httpFetchCount = ThreadSafeBox<Int>(0)
        let httpClient = HTTPClient(implementation: { request, _ in
            if request.method == .head { return .notFound() }
            if request.url.absoluteString.contains("Package.swift") {
                httpFetchCount.mutate { $0 += 1 }
                return .okay(body: Self.defaultManifest)
            }
            return .notFound()
        })

        // Pre-seed the disk cache for "aaa111" but NOT for "bbb222".
        let (cache, _) = try Self.makeMetadataCache()
        try cache.setManifest(
            owner: "owner", repo: "repo", sha: "aaa111",
            filename: "Package.swift", content: Self.defaultManifest
        )

        let container = try await Self.makeContainer(
            tags: [
                ResolvedTag(name: "1.0.0", commitSHA: "aaa111", version: Version(1, 0, 0)),
                ResolvedTag(name: "2.0.0", commitSHA: "bbb222", version: Version(2, 0, 0)),
            ],
            httpClient: httpClient,
            metadataCache: cache
        )

        _ = try await container.toolsVersionsAppropriateVersionsDescending()

        // Only bbb222 should have been fetched — aaa111 was in disk cache.
        #expect(httpFetchCount.get() == 1)
    }

    // MARK: - Failure taxonomy (container level)

    @Test("toolsVersion throws SourceArchiveResolverError when manifest fetch returns server error")
    func manifestFetchServerError() async throws {
        let httpClient = HTTPClient(implementation: { request, _ in
            if request.method == .head { return .notFound() }
            return .serverError()
        })

        let container = try await Self.makeContainer(
            tags: [ResolvedTag(name: "1.0.0", commitSHA: "aaa111", version: Version(1, 0, 0))],
            httpClient: httpClient
        )

        await #expect(throws: SourceArchiveResolverError.self) {
            _ = try await container.toolsVersion(for: Version(1, 0, 0))
        }
    }

    @Test("versionsAscending returns empty when no semver tags exist")
    func noSemverTags() async throws {
        let container = try await Self.makeContainer(tags: [])
        let versions = try await container.versionsAscending()
        #expect(versions.isEmpty)
    }

    @Test("toolsVersion throws StringError for version not in tag cache")
    func toolsVersionUnknownVersion() async throws {
        let container = try await Self.makeContainer(
            tags: [ResolvedTag(name: "1.0.0", commitSHA: "aaa111", version: Version(1, 0, 0))]
        )

        await #expect(throws: StringError.self) {
            _ = try await container.toolsVersion(for: Version(9, 9, 9))
        }
    }

    @Test("buildTagCache prefers non-v-prefixed tag regardless of input order")
    func tagDeduplicationOrder() async throws {
        // v1.0.0 appears BEFORE 1.0.0 — the shorter non-v tag should still win.
        let container = try await Self.makeContainer(
            tags: [
                ResolvedTag(name: "v1.0.0", commitSHA: "sha_v", version: Version(1, 0, 0)),
                ResolvedTag(name: "1.0.0", commitSHA: "sha_plain", version: Version(1, 0, 0)),
            ]
        )

        let tag = try await container.getTag(for: Version(1, 0, 0))
        #expect(tag == "1.0.0")
    }
}
