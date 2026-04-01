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
import PackageFingerprint
import PackageGraph
import PackageLoading
import PackageModel
@testable import Workspace
import Testing

import struct TSCBasic.ByteString
import struct TSCUtility.Version

/// Integration tests that exercise the full source archive workspace flow:
/// container routing → resolution → fetch → state persistence.
///
/// Uses `gitTagsProvider` injection on ``SourceArchiveResolver`` to avoid
/// real `git ls-remote` subprocesses, and mock HTTP for manifest/archive
/// content, matching the mock-based testing pattern used throughout SPM.
@Suite
private struct WorkspaceSourceArchiveIntegrationTests {

    private static let fakeLsRemoteOutput = """
    aaa111aaa111aaa111aaa111aaa111aaa111aaa1\trefs/tags/1.0.0
    bbb222bbb222bbb222bbb222bbb222bbb222bbb2\trefs/tags/1.1.0
    """

    private static let depManifestContent = """
    // swift-tools-version: 5.9
    import PackageDescription
    let package = Package(
        name: "Foo",
        products: [.library(name: "Foo", targets: ["Foo"])],
        targets: [.target(name: "Foo")]
    )
    """

    private static let rootManifestContent = """
    // swift-tools-version: 5.9
    import PackageDescription
    let package = Package(
        name: "MyPackage",
        dependencies: [
            .package(url: "https://github.com/test/foo.git", from: "1.0.0"),
        ],
        targets: [
            .target(name: "MyTarget", dependencies: [
                .product(name: "Foo", package: "foo"),
            ]),
        ]
    )
    """

    // MARK: - Shared helpers

    private static let depURL = SourceControlURL("https://github.com/test/foo.git")
    private static let depIdentity = PackageIdentity(url: depURL)
    private static let depRef = PackageReference(identity: depIdentity, kind: .remoteSourceControl(depURL))

    private static let sourceArchiveConfiguration = WorkspaceConfiguration(
        skipDependenciesUpdates: false,
        prefetchBasedOnResolvedFile: false,
        shouldCreateMultipleTestProducts: false,
        createREPLProduct: false,
        additionalFileRules: [],
        sharedDependenciesCacheEnabled: false,
        fingerprintCheckingMode: .strict,
        signingEntityCheckingMode: .strict,
        skipSignatureValidation: false,
        sourceControlToRegistryDependencyTransformation: .disabled,
        defaultRegistry: nil,
        manifestImportRestrictions: nil,
        usePrebuilts: false,
        prebuiltsDownloadURL: nil,
        prebuiltsRootCertPath: nil,
        useSourceArchives: true,
        pruneDependencies: false,
        traitConfiguration: .default
    )

    // MARK: - materializeSourceArchive tests

    /// Seeds the workspace's tag memoizer with `fakeLsRemoteOutput` so
    /// `materializeSourceArchive` doesn't invoke real `git ls-remote`.
    private static func seedTagMemoizer(on workspace: Workspace) async throws {
        _ = try await workspace.sourceArchiveTagMemoizer.memoize(depURL.absoluteString) {
            SourceArchiveResolver.filterSemverTags(
                SourceArchiveResolver.peelTags(
                    SourceArchiveResolver.parseLsRemoteOutput(fakeLsRemoteOutput)
                )
            )
        }
    }

    /// Pre-populates the workspace destination for the dep at version 1.1.0
    /// (simulates a prior prefetch that wrote the files without state persistence).
    private static func seedDestination(
        workspace: Workspace,
        fs: InMemoryFileSystem
    ) throws {
        let subpath = try RelativePath(validating: depIdentity.description)
            .appending(component: "1.1.0")
        let destPath = workspace.location.sourceArchiveDirectory.appending(subpath)
        try fs.createDirectory(destPath, recursive: true)
        try fs.writeFileContents(destPath.appending("Package.swift"), string: depManifestContent)
        try fs.createDirectory(destPath.appending(components: "Sources", "Foo"), recursive: true)
        try fs.writeFileContents(
            destPath.appending(components: "Sources", "Foo", "Foo.swift"),
            string: "public struct Foo {}"
        )
    }

    @Test("materializeSourceArchive downloads, extracts, and persists state with checksum")
    func materializeDownloadsAndExtracts() async throws {
        let fs = InMemoryFileSystem()
        let sandbox = AbsolutePath("/tmp/ws-sa-download/")
        try fs.createDirectory(sandbox, recursive: true)

        let downloadCalled = ThreadSafeBox<Bool>(false)
        let workspace = try Self.makeSourceArchiveWorkspace(
            sandbox: sandbox,
            fs: fs,
            downloadHTTPHandler: { request, _ in
                switch request.kind {
                case .download(let downloadFS, let destination):
                    downloadCalled.mutate { $0 = true }
                    try downloadFS.writeFileContents(destination, bytes: .init("fake-zip-bytes".utf8))
                    return .okay()
                case .generic:
                    return .okay()
                }
            }
        )
        try await Self.seedTagMemoizer(on: workspace)

        let observability = ObservabilitySystem.makeForTesting()
        let result = try await workspace.materializeSourceArchive(
            package: Self.depRef,
            version: Version(1, 1, 0),
            observabilityScope: observability.topScope
        )

        let destPath = try #require(result)
        #expect(downloadCalled.get() == true)
        #expect(fs.exists(destPath.appending("Package.swift")))

        let dep = try #require(await workspace.state.dependencies[Self.depIdentity])
        guard case .sourceArchiveDownload(let archiveState) = dep.state else {
            Issue.record("Expected .sourceArchiveDownload, got \(dep.state)")
            return
        }
        #expect(archiveState.version == Version(1, 1, 0))
        #expect(archiveState.tag == "1.1.0")
        #expect(archiveState.revision == "bbb222bbb222bbb222bbb222bbb222bbb222bbb2")
        #expect(archiveState.hasSubmodules == false)
        #expect(archiveState.checksum != nil)
    }

    @Test("materializeSourceArchive returns nil when a moved tag no longer matches the pinned revision")
    func materializeRejectsMovedTagForPinnedRevision() async throws {
        let fs = InMemoryFileSystem()
        let sandbox = AbsolutePath("/tmp/ws-sa-moved-tag/")
        try fs.createDirectory(sandbox, recursive: true)

        let workspace = try Self.makeSourceArchiveWorkspace(
            sandbox: sandbox,
            fs: fs
        )
        try await Self.seedTagMemoizer(on: workspace)

        let observability = ObservabilitySystem.makeForTesting()
        let result = try await workspace.materializeSourceArchive(
            package: Self.depRef,
            version: Version(1, 1, 0),
            pinnedRevision: "aaa111aaa111aaa111aaa111aaa111aaa111aaa1",
            observabilityScope: observability.topScope
        )

        #expect(result == nil)
        #expect(await workspace.state.dependencies[Self.depIdentity] == nil)
        #expect(observability.warnings.contains {
            $0.message.contains("Package.resolved pins aaa111aaa111aaa111aaa111aaa111aaa111aaa1")
        })
    }

    @Test("checksum recovered from fingerprint storage when destination already populated")
    func fingerprintRecoveryOnSkippedDownload() async throws {
        let fs = InMemoryFileSystem()
        let sandbox = AbsolutePath("/tmp/ws-sa-fp-recovery/")
        try fs.createDirectory(sandbox, recursive: true)

        let fingerprintStorage = MockPackageFingerprintStorage()
        let observability = ObservabilitySystem.makeForTesting()
        try fingerprintStorage.put(
            package: Self.depIdentity,
            version: Version(1, 1, 0),
            fingerprint: Fingerprint(
                origin: .sourceControl(Self.depURL),
                value: "abc123deadbeef",
                contentType: .sourceArchive
            ),
            observabilityScope: observability.topScope
        )

        let workspace = try Self.makeSourceArchiveWorkspace(
            sandbox: sandbox,
            fs: fs,
            fingerprintStorage: fingerprintStorage
        )
        try await Self.seedTagMemoizer(on: workspace)
        try Self.seedDestination(workspace: workspace, fs: fs)

        let result = try await workspace.materializeSourceArchive(
            package: Self.depRef,
            version: Version(1, 1, 0),
            observabilityScope: observability.topScope
        )

        try #require(result != nil)

        let dep = try #require(await workspace.state.dependencies[Self.depIdentity])
        guard case .sourceArchiveDownload(let archiveState) = dep.state else {
            Issue.record("Expected .sourceArchiveDownload, got \(dep.state)")
            return
        }
        #expect(archiveState.checksum == "abc123deadbeef")
    }

    @Test("checksum persisted as nil when destination is pre-populated and no fingerprint exists")
    func fingerprintRecoveryGracefulNil() async throws {
        let fs = InMemoryFileSystem()
        let sandbox = AbsolutePath("/tmp/ws-sa-fp-nil/")
        try fs.createDirectory(sandbox, recursive: true)

        // Empty fingerprint storage — no prior checksum stored.
        let fingerprintStorage = MockPackageFingerprintStorage()

        let workspace = try Self.makeSourceArchiveWorkspace(
            sandbox: sandbox,
            fs: fs,
            fingerprintStorage: fingerprintStorage
        )
        try await Self.seedTagMemoizer(on: workspace)
        try Self.seedDestination(workspace: workspace, fs: fs)

        let observability = ObservabilitySystem.makeForTesting()
        let result = try await workspace.materializeSourceArchive(
            package: Self.depRef,
            version: Version(1, 1, 0),
            observabilityScope: observability.topScope
        )

        // Should succeed (destination was on disk).
        try #require(result != nil)

        // No fingerprint was stored, so checksum should be nil — not an error.
        let dep = try #require(await workspace.state.dependencies[Self.depIdentity])
        guard case .sourceArchiveDownload(let archiveState) = dep.state else {
            Issue.record("Expected .sourceArchiveDownload, got \(dep.state)")
            return
        }
        #expect(archiveState.checksum == nil)
        // No error diagnostics should have been emitted.
        #expect(!observability.diagnostics.contains { $0.severity == .error })
    }

    @Test("materializeSourceArchive uses shallow clone for packages with submodules")
    func materializeShallowClone() async throws {
        let fs = InMemoryFileSystem()
        let sandbox = AbsolutePath("/tmp/ws-sa-shallow/")
        try fs.createDirectory(sandbox, recursive: true)

        // The sourceArchiveHTTPClient handles BOTH resolver probes (manifest,
        // .gitmodules) AND archive downloads.
        let workspace = try Self.makeSourceArchiveWorkspace(
            sandbox: sandbox,
            fs: fs,
            downloadHTTPHandler: { request, _ in
                switch request.kind {
                case .download(let downloadFS, let destination):
                    try downloadFS.writeFileContents(destination, bytes: .init("fake".utf8))
                    return .okay()
                case .generic:
                    if request.method == .head { return .notFound() }
                    if request.url.absoluteString.contains(".gitmodules") {
                        return .okay(body: "[submodule \"vendor\"]\n\tpath = vendor\n\turl = https://example.com/vendor.git")
                    }
                    if request.url.absoluteString.contains("Package.swift") {
                        return .okay(body: Self.depManifestContent)
                    }
                    return .notFound()
                }
            }
        )
        try await Self.seedTagMemoizer(on: workspace)

        let observability = ObservabilitySystem.makeForTesting(verbose: false)
        let result = try await workspace.materializeSourceArchive(
            package: Self.depRef,
            version: Version(1, 1, 0),
            observabilityScope: observability.topScope
        )

        // Shallow clone fails (no real git) — verify the submodule detection
        // worked and the fallback was graceful.
        #expect(result == nil)
        #expect(observability.diagnostics.contains {
            $0.message.contains("source archive download failed") && $0.message.contains("falling back to git")
        })
        #expect(!observability.diagnostics.contains {
            $0.message.contains("failed downloading source archive")
        })
    }

    // MARK: - Prefetch behavior

    @Test("prefetch skips already-materialized packages, restores from cache, and does not persist state")
    func prefetchBehavior() async throws {
        let fs = InMemoryFileSystem()
        let sandbox = AbsolutePath("/tmp/ws-prefetch/")
        try fs.createDirectory(sandbox, recursive: true)

        let scratchDir = sandbox.appending(".build")
        let location = Workspace.Location(
            scratchDirectory: scratchDir,
            editsDirectory: sandbox.appending("edits"),
            resolvedVersionsFile: scratchDir.appending("Package.resolved"),
            localConfigurationDirectory: scratchDir.appending("config"),
            sharedConfigurationDirectory: nil,
            sharedSecurityDirectory: nil,
            sharedCacheDirectory: sandbox.appending("shared-cache")
        )

        let rootPath = sandbox.appending("Root")
        try fs.createDirectory(rootPath, recursive: true)
        try fs.writeFileContents(rootPath.appending("Package.swift"), string: """
        // swift-tools-version: 5.9
        import PackageDescription
        let package = Package(name: "Root")
        """)

        let manifest = "// swift-tools-version: 5.9\nimport PackageDescription\nlet package = Package(name: \"Pkg\")\n"

        // Package A: already materialized in workspace destination.
        let identityA = PackageIdentity(url: SourceControlURL("https://github.com/test/pkg-a.git"))
        let destA = location.sourceArchiveDirectory
            .appending(try RelativePath(validating: identityA.description))
            .appending(component: "1.0.0")
        try fs.createDirectory(destA, recursive: true)
        try fs.writeFileContents(destA.appending("Package.swift"), string: manifest)

        // Package B: in shared cache but not in workspace.
        let identityB = PackageIdentity(url: SourceControlURL("https://github.com/test/pkg-b.git"))
        let cacheB = location.sharedSourceArchiveCacheDirectory!
            .appending(try RelativePath(validating: identityB.description))
            .appending(component: "2.0.0")
        try fs.createDirectory(cacheB, recursive: true)
        try fs.writeFileContents(cacheB.appending("Package.swift"), string: manifest)

        try fs.createMockToolchain()
        let hostToolchain = try UserToolchain.mockHostToolchain(fs)

        var config = Self.sourceArchiveConfiguration
        config.sharedDependenciesCacheEnabled = true
        let workspace = try Workspace._init(
            fileSystem: fs,
            environment: .current,
            location: location,
            configuration: config,
            customHostToolchain: hostToolchain,
            customManifestLoader: ManifestLoader(toolchain: hostToolchain)
        )

        let observability = ObservabilitySystem.makeForTesting()

        let urlA = SourceControlURL("https://github.com/test/pkg-a.git")
        let urlB = SourceControlURL("https://github.com/test/pkg-b.git")
        let refA = PackageReference(identity: identityA, kind: .remoteSourceControl(urlA))
        let refB = PackageReference(identity: identityB, kind: .remoteSourceControl(urlB))

        let changes: [(PackageReference, Workspace.PackageStateChange)] = [
            (refA, .added(.init(requirement: .version(Version(1, 0, 0)), products: .everything))),
            (refB, .added(.init(requirement: .version(Version(2, 0, 0)), products: .everything))),
        ]

        await workspace.prefetchSourceArchives(
            for: changes,
            observabilityScope: observability.topScope
        )

        // A was already on disk → skipped (still there).
        #expect(fs.exists(destA.appending("Package.swift")))

        // B was restored from shared cache → now in workspace destination.
        let destB = location.sourceArchiveDirectory
            .appending(try RelativePath(validating: identityB.description))
            .appending(component: "2.0.0")
        #expect(fs.exists(destB.appending("Package.swift")))

        // Prefetch does NOT persist managed dependency state.
        let stateA = await workspace.state.dependencies[identityA]
        let stateB = await workspace.state.dependencies[identityB]
        #expect(stateA == nil)
        #expect(stateB == nil)
    }
    @Test("strict checksum mismatch propagates through materializeSourceArchive without fallback")
    func strictChecksumMismatchPropagates() async throws {
        let fs = InMemoryFileSystem()
        let sandbox = AbsolutePath("/tmp/ws-sa-strict-checksum/")
        try fs.createDirectory(sandbox, recursive: true)

        let fingerprintStorage = MockPackageFingerprintStorage()
        let observability = ObservabilitySystem.makeForTesting()
        try fingerprintStorage.put(
            package: Self.depIdentity,
            version: Version(1, 1, 0),
            fingerprint: Fingerprint(
                origin: .sourceControl(Self.depURL),
                value: "0000000000000000000000000000000000000000000000000000000000000000",
                contentType: .sourceArchive
            ),
            observabilityScope: observability.topScope
        )

        let workspace = try Self.makeSourceArchiveWorkspace(
            sandbox: sandbox,
            fs: fs,
            fingerprintStorage: fingerprintStorage
        )
        try await Self.seedTagMemoizer(on: workspace)

        await #expect(throws: SourceArchiveChecksumMismatchError.self) {
            try await workspace.materializeSourceArchive(
                package: Self.depRef,
                version: Version(1, 1, 0),
                observabilityScope: observability.topScope
            )
        }

        let hasFallbackWarning = observability.diagnostics.contains {
            $0.message.contains("falling back to git")
        }
        #expect(!hasFallbackWarning,
            "strict checksum mismatch must not silently fall back to git")

        let hasMisleadingDiagnostic = observability.diagnostics.contains {
            $0.message.contains("failed to get source archive fingerprint")
        }
        #expect(!hasMisleadingDiagnostic,
            "checksum mismatch should not emit misleading fingerprint-lookup diagnostic")
    }

    // MARK: - getContainer probe fallthrough

    @Test("getContainer probe failure emits info diagnostic and falls through to git")
    func getContainerProbeFallthrough() async throws {
        let fs = InMemoryFileSystem()
        let sandbox = AbsolutePath("/tmp/ws-probe-fallthrough/")
        let downloadHTTPClient = HTTPClient { request, _ in
            switch request.kind {
            case .download:
                return .serverError()
            case .generic:
                if request.method == .head { return .notFound() }
                return .serverError()
            }
        }

        let workspace = try Self.makeGetContainerWorkspace(
            sandbox: sandbox,
            fs: fs,
            downloadHTTPClient: downloadHTTPClient
        )

        try await Self.seedTagMemoizer(on: workspace)

        let observability = ObservabilitySystem.makeForTesting()
        do {
            _ = try await workspace.getContainer(
                for: Self.depRef,
                updateStrategy: .never,
                observabilityScope: observability.topScope
            )
        } catch {
            // Expected — git fallback also fails (no real repo).
        }

        #expect(observability.diagnostics.contains {
            $0.message.contains("source archive path unavailable") && $0.message.contains("using git")
        })
    }

    @Test("getContainer falls back to git when recent tags fail even if an older tag is valid")
    func getContainerRecentTagFailuresFallBackToGit() async throws {
        let fs = InMemoryFileSystem()
        let sandbox = AbsolutePath("/tmp/ws-probe-recent-tags/")
        let lsRemoteOutput = """
        aaa111aaa111aaa111aaa111aaa111aaa111aaa1\trefs/tags/1.0.0
        bbb222bbb222bbb222bbb222bbb222bbb222bbb2\trefs/tags/1.1.0
        ccc333ccc333ccc333ccc333ccc333ccc333ccc3\trefs/tags/1.2.0
        ddd444ddd444ddd444ddd444ddd444ddd444ddd4\trefs/tags/1.3.0
        """

        let downloadHTTPClient = HTTPClient { request, _ in
            switch request.kind {
            case .download:
                return .serverError()
            case .generic:
                if request.method == .head { return .notFound() }
                let url = request.url.absoluteString
                if url.contains("/aaa111aaa111aaa111aaa111aaa111aaa111aaa1/Package.swift") {
                    return .okay(body: Self.depManifestContent)
                }
                return .serverError()
            }
        }

        let workspace = try Self.makeGetContainerWorkspace(
            sandbox: sandbox,
            fs: fs,
            downloadHTTPClient: downloadHTTPClient
        )

        _ = try await workspace.sourceArchiveTagMemoizer.memoize(Self.depURL.absoluteString) {
            SourceArchiveResolver.filterSemverTags(
                SourceArchiveResolver.peelTags(
                    SourceArchiveResolver.parseLsRemoteOutput(lsRemoteOutput)
                )
            )
        }

        let observability = ObservabilitySystem.makeForTesting()
        do {
            _ = try await workspace.getContainer(
                for: Self.depRef,
                updateStrategy: .never,
                observabilityScope: observability.topScope
            )
        } catch {
            // Expected — git fallback also fails because there is no real repo.
        }

        #expect(observability.diagnostics.contains {
            $0.message.contains("source archive path unavailable") && $0.message.contains("using git")
        })
    }

    // MARK: - Failure taxonomy

    /// Overridable transport helper — each test overrides exactly one failure point.
    /// Default implementations produce valid 200 responses for all endpoints.
    private static func makeGetContainerWorkspace(
        sandbox: AbsolutePath,
        fs: InMemoryFileSystem,
        downloadHTTPClient: HTTPClient
    ) throws -> Workspace {
        try fs.createDirectory(sandbox, recursive: true)

        let rootPath = sandbox.appending("Root")
        try fs.createDirectory(rootPath, recursive: true)
        try fs.writeFileContents(rootPath.appending("Package.swift"), string: Self.rootManifestContent)
        try fs.createDirectory(rootPath.appending(components: "Sources", "MyTarget"), recursive: true)
        try fs.writeFileContents(
            rootPath.appending(components: "Sources", "MyTarget", "main.swift"),
            string: "import Foo"
        )

        let scratchDir = sandbox.appending(".build")
        let location = Workspace.Location(
            scratchDirectory: scratchDir,
            editsDirectory: sandbox.appending("edits"),
            resolvedVersionsFile: scratchDir.appending("Package.resolved"),
            localConfigurationDirectory: scratchDir.appending("config"),
            sharedConfigurationDirectory: nil,
            sharedSecurityDirectory: nil,
            sharedCacheDirectory: nil
        )

        try fs.createMockToolchain()
        let hostToolchain = try UserToolchain.mockHostToolchain(fs)

        return try Workspace._init(
            fileSystem: fs,
            environment: .current,
            location: location,
            configuration: Self.sourceArchiveConfiguration,
            customHostToolchain: hostToolchain,
            customManifestLoader: ManifestLoader(toolchain: hostToolchain),
            customSourceArchiveHTTPClient: downloadHTTPClient
        )
    }

    private static func makeSourceArchiveWorkspace(
        sandbox: AbsolutePath,
        fs: InMemoryFileSystem,
        gitTagsProvider: (@Sendable (String) async throws -> String)? = nil,
        manifestHTTPHandler: HTTPClient.Implementation? = nil,
        downloadHTTPHandler: HTTPClient.Implementation? = nil,
        archiver: (any Archiver)? = nil,
        fingerprintStorage: (any PackageFingerprintStorage)? = nil
    ) throws -> Workspace {
        let rootPath = sandbox.appending("Root")
        try fs.createDirectory(rootPath, recursive: true)
        try fs.writeFileContents(rootPath.appending("Package.swift"), string: Self.rootManifestContent)
        try fs.createDirectory(rootPath.appending(components: "Sources", "MyTarget"), recursive: true)
        try fs.writeFileContents(
            rootPath.appending(components: "Sources", "MyTarget", "main.swift"),
            string: "import Foo"
        )

        let scratchDir = sandbox.appending(".build")
        let location = Workspace.Location(
            scratchDirectory: scratchDir,
            editsDirectory: sandbox.appending("edits"),
            resolvedVersionsFile: scratchDir.appending("Package.resolved"),
            localConfigurationDirectory: scratchDir.appending("config"),
            sharedConfigurationDirectory: nil,
            sharedSecurityDirectory: nil,
            sharedCacheDirectory: nil
        )

        let resolvedGitTagsProvider = gitTagsProvider ?? { _ in Self.fakeLsRemoteOutput }

        let resolvedManifestHTTPHandler: HTTPClient.Implementation = manifestHTTPHandler ?? { request, _ in
            if request.method == .head { return .notFound() }
            if request.url.absoluteString.contains("Package.swift") {
                return .okay(body: Self.depManifestContent)
            }
            if request.url.absoluteString.contains(".gitmodules") {
                return .notFound()
            }
            return .notFound()
        }

        let resolvedDownloadHTTPHandler: HTTPClient.Implementation = downloadHTTPHandler ?? { request, _ in
            switch request.kind {
            case .download(let downloadFS, let destination):
                try downloadFS.writeFileContents(destination, bytes: .init("fake-zip".utf8))
                return .okay()
            case .generic:
                return .okay()
            }
        }

        let resolvedArchiver: any Archiver = archiver ?? MockArchiver(handler: { _, _, destinationPath, completion in
            let topLevel = destinationPath.appending(component: "package-1.0.0")
            try fs.createDirectory(topLevel, recursive: true)
            try fs.writeFileContents(
                topLevel.appending(component: "Package.swift"),
                string: Self.depManifestContent
            )
            try fs.createDirectory(topLevel.appending(components: "Sources", "Foo"), recursive: true)
            try fs.writeFileContents(
                topLevel.appending(components: "Sources", "Foo", "Foo.swift"),
                string: "public struct Foo {}"
            )
            completion(.success(()))
        })

        let httpClient = HTTPClient(implementation: resolvedManifestHTTPHandler)
        let downloadHTTPClient = HTTPClient(implementation: resolvedDownloadHTTPHandler)

        let resolver = SourceArchiveResolver(
            httpClient: httpClient,
            authorizationProvider: nil,
            gitTagsProvider: resolvedGitTagsProvider
        )

        let containerProvider = SourceArchiveTestContainerProvider(
            resolver: resolver,
            httpClient: httpClient,
            fileSystem: fs,
            manifestLoader: ManifestLoader(toolchain: try UserToolchain.mockHostToolchain(fs))
        )

        try fs.createMockToolchain()
        let hostToolchain = try UserToolchain.mockHostToolchain(fs)

        return try Workspace._init(
            fileSystem: fs,
            environment: .current,
            location: location,
            configuration: Self.sourceArchiveConfiguration,
            customFingerprints: fingerprintStorage,
            customHostToolchain: hostToolchain,
            customManifestLoader: ManifestLoader(toolchain: hostToolchain),
            customPackageContainerProvider: containerProvider,
            customSourceArchiveHTTPClient: downloadHTTPClient,
            customSourceArchiveArchiver: resolvedArchiver
        )
    }

    enum DownloadFailureMode: CaseIterable, CustomTestStringConvertible {
        case httpError
        case extractionError

        var testDescription: String {
            switch self {
            case .httpError: return "HTTP 503 on archive download"
            case .extractionError: return "corrupt archive extraction"
            }
        }

        /// Snippet that must appear in the inner error portion of the diagnostic.
        var expectedErrorSnippet: String {
            switch self {
            case .httpError: return "HTTP 503"
            case .extractionError: return "extraction failed: corrupt archive"
            }
        }
    }

    @Test("materializeSourceArchive returns nil with diagnostic containing package identity and error", arguments: DownloadFailureMode.allCases)
    func downloadFailureFallsBack(mode: DownloadFailureMode) async throws {
        let fs = InMemoryFileSystem()
        let sandbox = AbsolutePath("/tmp/ws-fail-\(mode.hashValue)/")
        try fs.createDirectory(sandbox, recursive: true)

        let workspace: Workspace
        switch mode {
        case .httpError:
            workspace = try Self.makeSourceArchiveWorkspace(
                sandbox: sandbox,
                fs: fs,
                downloadHTTPHandler: { request, _ in
                    switch request.kind {
                    case .download:
                        return HTTPClientResponse(statusCode: 503)
                    case .generic:
                        return .okay()
                    }
                }
            )
        case .extractionError:
            workspace = try Self.makeSourceArchiveWorkspace(
                sandbox: sandbox,
                fs: fs,
                archiver: MockArchiver(handler: { _, _, _, completion in
                    completion(.failure(StringError("extraction failed: corrupt archive")))
                })
            )
        }
        try await Self.seedTagMemoizer(on: workspace)

        let observability = ObservabilitySystem.makeForTesting(verbose: false)
        let result = try await workspace.materializeSourceArchive(
            package: Self.depRef,
            version: Version(1, 1, 0),
            observabilityScope: observability.topScope
        )

        #expect(result == nil)

        let fallbackWarning = try #require(
            observability.diagnostics.first {
                $0.severity == .warning && $0.message.contains("falling back to git")
            },
            "expected a fallback warning diagnostic"
        )
        #expect(fallbackWarning.message.contains("foo"))
        #expect(fallbackWarning.message.contains(mode.expectedErrorSnippet))
    }
}

// MARK: - Test Container Provider

private struct SourceArchiveTestContainerProvider: PackageContainerProvider {
    let resolver: SourceArchiveResolver
    let httpClient: HTTPClient
    let fileSystem: any FileSystem
    let manifestLoader: any ManifestLoaderProtocol

    func getContainer(
        for package: PackageReference,
        updateStrategy: ContainerUpdateStrategy,
        observabilityScope: ObservabilityScope
    ) async throws -> any PackageContainer {
        switch package.kind {
        case .root, .fileSystem:
            return try FileSystemPackageContainer(
                package: package,
                identityResolver: DefaultIdentityResolver(),
                dependencyMapper: DefaultDependencyMapper(
                    identityResolver: DefaultIdentityResolver()
                ),
                manifestLoader: manifestLoader,
                currentToolsVersion: .current,
                fileSystem: fileSystem,
                observabilityScope: observabilityScope
            )
        case .remoteSourceControl(let url):
            let cachePath = AbsolutePath("/tmp/sa-test-cache")
            try fileSystem.createDirectory(cachePath, recursive: true)
            let metadataCache = SourceArchiveMetadataCache(
                fileSystem: fileSystem,
                cachePath: cachePath
            )
            let provider: any SourceArchiveProvider =
                GitHubSourceArchiveProvider.make(for: url)
                ?? TestFallbackProvider(url: url)

            return SourceArchivePackageContainer(
                package: package,
                provider: provider,
                resolver: resolver,
                metadataCache: metadataCache,
                manifestLoader: manifestLoader,
                identityResolver: DefaultIdentityResolver(),
                dependencyMapper: DefaultDependencyMapper(
                    identityResolver: DefaultIdentityResolver()
                ),
                currentToolsVersion: .current,
                observabilityScope: observabilityScope
            )
        default:
            throw StringError("unsupported package kind: \(package.kind)")
        }
    }
}

private struct TestFallbackProvider: SourceArchiveProvider {
    let url: SourceControlURL

    var cacheKey: (owner: String, repo: String) { ("_fallback", url.absoluteString) }

    func archiveURL(for tag: String) -> URL {
        URL(string: "\(url.absoluteString)/archive/\(tag).zip")!
    }

    func rawFileURL(for path: String, sha: String) -> URL {
        URL(string: "\(url.absoluteString)/raw/\(sha)/\(path)")!
    }
}
