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
import _InternalTestSupport
import PackageFingerprint
import PackageModel
@testable import Workspace
import Testing

import struct TSCBasic.ByteString
import protocol TSCBasic.HashAlgorithm
import struct TSCBasic.SHA256
import struct TSCUtility.Version

@Suite(.tags(.TestSize.small))
private struct SourceArchiveDownloaderTests {

    // MARK: - Shared constants & helpers

    private static let packageIdentity = PackageIdentity.plain("testpackage")
    private static let version: Version = "1.0.0"
    private static let archiveURL = URL(string: "https://github.com/test/testpackage/archive/refs/tags/1.0.0.zip")!
    private static let sourceURL: SourceControlURL = "https://github.com/test/testpackage.git"
    private static let archiveContent = Data("fake-archive-content".utf8)

    /// Creates a mock HTTP client that writes `archiveContent` to the download destination.
    private static func mockHTTPClient(
        fileSystem: any FileSystem,
        archiveContent: Data = SourceArchiveDownloaderTests.archiveContent
    ) -> HTTPClient {
        HTTPClient { request, _ in
            switch request.kind {
            case .download(let fs, let destination):
                try fs.writeFileContents(destination, bytes: ByteString(archiveContent))
                return .okay()
            case .generic:
                return .okay()
            }
        }
    }

    /// Creates a mock archiver that simulates extraction with a top-level directory containing Package.swift.
    private static func mockArchiver(fileSystem: any FileSystem) -> MockArchiver {
        MockArchiver(handler: { _, _, destinationPath, completion in
            let topLevel = destinationPath.appending(component: "package-1.0.0")
            try fileSystem.createDirectory(topLevel, recursive: true)
            try fileSystem.writeFileContents(
                topLevel.appending(component: Manifest.filename),
                string: "// swift-tools-version: 5.9"
            )
            completion(.success(()))
        })
    }

    /// Creates a mock archiver that produces an archive without Package.swift.
    private static func mockArchiverNoManifest(fileSystem: any FileSystem) -> MockArchiver {
        MockArchiver(handler: { _, _, destinationPath, completion in
            let topLevel = destinationPath.appending(component: "package-1.0.0")
            try fileSystem.createDirectory(topLevel, recursive: true)
            try fileSystem.writeFileContents(
                topLevel.appending(component: "README.md"),
                string: "# Hello"
            )
            completion(.success(()))
        })
    }

    /// Convenience to call `downloadSourceArchive` with standard defaults, allowing overrides.
    private static func performDownload(
        downloader: SourceArchiveDownloader,
        destinationPath: AbsolutePath,
        cachePath: AbsolutePath? = nil,
        checksumAlgorithm: SHA256 = SHA256(),
        fingerprintStorage: MockPackageFingerprintStorage? = nil,
        fingerprintCheckingMode: FingerprintCheckingMode = .strict,
        observabilityScope: ObservabilityScope
    ) async throws {
        try await downloader.downloadSourceArchive(
            package: packageIdentity,
            version: version,
            archiveURL: archiveURL,
            cachePath: cachePath,
            destinationPath: destinationPath,
            checksumAlgorithm: checksumAlgorithm,
            fingerprintStorage: fingerprintStorage,
            fingerprintCheckingMode: fingerprintCheckingMode,
            sourceURL: sourceURL,
            authorizationProvider: nil,
            progressHandler: nil,
            observabilityScope: observabilityScope
        )
    }

    // MARK: - Download & fingerprint tests

    @Test
    func downloadAndExtractStoresFingerprint() async throws {
        let fileSystem = InMemoryFileSystem()
        let fingerprintStorage = MockPackageFingerprintStorage()
        let observability = ObservabilitySystem.makeForTesting()
        let checksumAlgorithm = SHA256()

        let downloader = SourceArchiveDownloader(
            httpClient: Self.mockHTTPClient(fileSystem: fileSystem),
            archiver: Self.mockArchiver(fileSystem: fileSystem),
            fileSystem: fileSystem
        )

        let destinationPath = AbsolutePath("/workspace/testpackage")

        try await Self.performDownload(
            downloader: downloader,
            destinationPath: destinationPath,
            checksumAlgorithm: checksumAlgorithm,
            fingerprintStorage: fingerprintStorage,
            observabilityScope: observability.topScope
        )

        #expect(fileSystem.exists(destinationPath.appending(component: Manifest.filename)))

        let expectedChecksum = checksumAlgorithm.hash(.init(Self.archiveContent))
            .hexadecimalRepresentation
        let stored = try fingerprintStorage.get(
            package: Self.packageIdentity,
            version: Self.version,
            kind: .sourceControl,
            contentType: .sourceArchive,
            observabilityScope: observability.topScope
        )
        #expect(stored.value == expectedChecksum)
    }

    @Test
    func secondDownloadWithMatchingChecksumSucceeds() async throws {
        let fileSystem = InMemoryFileSystem()
        let observability = ObservabilitySystem.makeForTesting()
        let checksumAlgorithm = SHA256()
        let expectedChecksum = checksumAlgorithm.hash(.init(Self.archiveContent))
            .hexadecimalRepresentation

        let fingerprintStorage = MockPackageFingerprintStorage()
        try fingerprintStorage.put(
            package: Self.packageIdentity,
            version: Self.version,
            fingerprint: Fingerprint(
                origin: .sourceControl(Self.sourceURL),
                value: expectedChecksum,
                contentType: .sourceArchive
            ),
            observabilityScope: observability.topScope
        )

        let downloader = SourceArchiveDownloader(
            httpClient: Self.mockHTTPClient(fileSystem: fileSystem),
            archiver: Self.mockArchiver(fileSystem: fileSystem),
            fileSystem: fileSystem
        )

        let destinationPath = AbsolutePath("/workspace/testpackage2")

        try await Self.performDownload(
            downloader: downloader,
            destinationPath: destinationPath,
            checksumAlgorithm: checksumAlgorithm,
            fingerprintStorage: fingerprintStorage,
            observabilityScope: observability.topScope
        )

        #expect(fileSystem.exists(destinationPath.appending(component: Manifest.filename)))
    }

    @Test
    func checksumMismatchInStrictModeThrows() async throws {
        let fileSystem = InMemoryFileSystem()
        let observability = ObservabilitySystem.makeForTesting()

        let fingerprintStorage = MockPackageFingerprintStorage()
        try fingerprintStorage.put(
            package: Self.packageIdentity,
            version: Self.version,
            fingerprint: Fingerprint(
                origin: .sourceControl(Self.sourceURL),
                value: "0000000000000000000000000000000000000000000000000000000000000000",
                contentType: .sourceArchive
            ),
            observabilityScope: observability.topScope
        )

        let downloader = SourceArchiveDownloader(
            httpClient: Self.mockHTTPClient(fileSystem: fileSystem),
            archiver: Self.mockArchiver(fileSystem: fileSystem),
            fileSystem: fileSystem
        )

        let destinationPath = AbsolutePath("/workspace/testpackage3")

        await #expect(throws: SourceArchiveChecksumMismatchError.self) {
            try await Self.performDownload(
                downloader: downloader,
                destinationPath: destinationPath,
                fingerprintStorage: fingerprintStorage,
                observabilityScope: observability.topScope
            )
        }

        let hasMisleadingDiagnostic = observability.diagnostics.contains {
            $0.message.contains("failed to get source archive fingerprint")
        }
        #expect(!hasMisleadingDiagnostic,
            "checksum mismatch should not emit 'failed to get fingerprint' diagnostic")
    }

    // MARK: - Skip-download scenarios (parameterized)

    /// Describes a scenario where the download/extract step should be skipped entirely.
    enum SkipScenario: String, CaseIterable, CustomTestStringConvertible {
        case cacheHit
        case workspaceAlreadyPopulated

        var testDescription: String {
            switch self {
            case .cacheHit: return "cache hit skips download"
            case .workspaceAlreadyPopulated: return "workspace already populated skips everything"
            }
        }
    }

    @Test(arguments: SkipScenario.allCases)
    func skipDownloadWhenAlreadyAvailable(scenario: SkipScenario) async throws {
        let fileSystem = InMemoryFileSystem()
        let observability = ObservabilitySystem.makeForTesting()

        let destinationPath = AbsolutePath("/workspace/testpackage-skip")
        var cachePath: AbsolutePath? = nil

        switch scenario {
        case .cacheHit:
            let cache = AbsolutePath("/cache/testpackage/1.0.0")
            try fileSystem.createDirectory(cache, recursive: true)
            try fileSystem.writeFileContents(
                cache.appending(component: Manifest.filename),
                string: "// swift-tools-version: 5.9"
            )
            cachePath = cache

        case .workspaceAlreadyPopulated:
            try fileSystem.createDirectory(destinationPath, recursive: true)
            try fileSystem.writeFileContents(
                destinationPath.appending(component: Manifest.filename),
                string: "// swift-tools-version: 5.9"
            )
        }

        // HTTP client and archiver that fail if invoked -- proving they are not called.
        let httpClient = HTTPClient { _, _ in
            throw StringError("download should not be called in skip scenario: \(scenario)")
        }
        let archiver = MockArchiver(handler: { _, _, _, _ in
            throw StringError("archiver should not be called in skip scenario: \(scenario)")
        })

        let downloader = SourceArchiveDownloader(
            httpClient: httpClient,
            archiver: archiver,
            fileSystem: fileSystem
        )

        try await Self.performDownload(
            downloader: downloader,
            destinationPath: destinationPath,
            cachePath: cachePath,
            observabilityScope: observability.topScope
        )

        #expect(fileSystem.exists(destinationPath.appending(component: Manifest.filename)))
    }

    @Test
    func rejectsArchiveWithoutPackageSwift() async throws {
        let fileSystem = InMemoryFileSystem()
        let observability = ObservabilitySystem.makeForTesting()

        let downloader = SourceArchiveDownloader(
            httpClient: Self.mockHTTPClient(fileSystem: fileSystem),
            archiver: Self.mockArchiverNoManifest(fileSystem: fileSystem),
            fileSystem: fileSystem
        )

        let destinationPath = AbsolutePath("/workspace/testpackage6")

        await #expect(throws: StringError.self) {
            try await Self.performDownload(
                downloader: downloader,
                destinationPath: destinationPath,
                observabilityScope: observability.topScope
            )
        }
    }

    // MARK: - Additional coverage

    @Test
    func checksumMismatchInWarnModeEmitsWarningButSucceeds() async throws {
        let fileSystem = InMemoryFileSystem()
        let observability = ObservabilitySystem.makeForTesting()

        let fingerprintStorage = MockPackageFingerprintStorage()
        try fingerprintStorage.put(
            package: Self.packageIdentity,
            version: Self.version,
            fingerprint: Fingerprint(
                origin: .sourceControl(Self.sourceURL),
                value: "0000000000000000000000000000000000000000000000000000000000000000",
                contentType: .sourceArchive
            ),
            observabilityScope: observability.topScope
        )

        let downloader = SourceArchiveDownloader(
            httpClient: Self.mockHTTPClient(fileSystem: fileSystem),
            archiver: Self.mockArchiver(fileSystem: fileSystem),
            fileSystem: fileSystem
        )

        let destinationPath = AbsolutePath("/workspace/testpackage-warn")

        // In .warn mode, mismatch should NOT throw
        try await Self.performDownload(
            downloader: downloader,
            destinationPath: destinationPath,
            fingerprintStorage: fingerprintStorage,
            fingerprintCheckingMode: .warn,
            observabilityScope: observability.topScope
        )

        #expect(fileSystem.exists(destinationPath.appending(component: Manifest.filename)))
        // Verify a warning was emitted about the checksum mismatch
        let warning = try #require(observability.warnings.first { $0.message.contains("checksum mismatch") })
        #expect(warning.message.contains("\(Self.packageIdentity)"))
        #expect(warning.message.contains("\(Self.version)"))
    }

    @Test
    func nilFingerprintStorageSkipsTOFUAndSucceeds() async throws {
        let fileSystem = InMemoryFileSystem()
        let observability = ObservabilitySystem.makeForTesting()

        let downloader = SourceArchiveDownloader(
            httpClient: Self.mockHTTPClient(fileSystem: fileSystem),
            archiver: Self.mockArchiver(fileSystem: fileSystem),
            fileSystem: fileSystem
        )

        let destinationPath = AbsolutePath("/workspace/testpackage-nofp")

        // Pass nil fingerprintStorage — should succeed without TOFU
        try await Self.performDownload(
            downloader: downloader,
            destinationPath: destinationPath,
            fingerprintStorage: nil,
            observabilityScope: observability.topScope
        )

        #expect(fileSystem.exists(destinationPath.appending(component: Manifest.filename)))
    }

    @Test
    func httpNon200ResponseThrowsError() async throws {
        let fileSystem = InMemoryFileSystem()
        let observability = ObservabilitySystem.makeForTesting()

        // HTTP client that returns a 500 status after writing the file (simulating server error)
        let httpClient = HTTPClient { request, _ in
            switch request.kind {
            case .download(let fs, let destination):
                try fs.writeFileContents(destination, bytes: ByteString(Self.archiveContent))
                return HTTPClientResponse(statusCode: 500)
            case .generic:
                return HTTPClientResponse(statusCode: 500)
            }
        }

        let downloader = SourceArchiveDownloader(
            httpClient: httpClient,
            archiver: Self.mockArchiver(fileSystem: fileSystem),
            fileSystem: fileSystem
        )

        let destinationPath = AbsolutePath("/workspace/testpackage-500")

        await #expect(throws: StringError.self) {
            try await Self.performDownload(
                downloader: downloader,
                destinationPath: destinationPath,
                observabilityScope: observability.topScope
            )
        }
    }

    // MARK: - Authorization provider tests

    @Test
    func downloadWithAuthorizationProviderUsesAuthHeader() async throws {
        let fileSystem = InMemoryFileSystem()
        let observability = ObservabilitySystem.makeForTesting()
        let capturedAuthProvider = ThreadSafeBox<((URL) -> String?)?>(nil)

        let httpClient = HTTPClient { request, _ in
            switch request.kind {
            case .download(let fs, let destination):
                capturedAuthProvider.mutate { $0 = request.options.authorizationProvider }
                try fs.writeFileContents(destination, bytes: ByteString(Self.archiveContent))
                return .okay()
            case .generic:
                return .okay()
            }
        }

        let downloader = SourceArchiveDownloader(
            httpClient: httpClient,
            archiver: Self.mockArchiver(fileSystem: fileSystem),
            fileSystem: fileSystem
        )

        let destinationPath = AbsolutePath("/workspace/testpackage-auth")

        /// A mock authorization provider for testing the auth header branch.
        struct TestAuthProvider: AuthorizationProvider {
            func authentication(for url: URL) -> (user: String, password: String)? {
                return (user: "token", password: "ghp_secret123")
            }
        }

        try await downloader.downloadSourceArchive(
            package: Self.packageIdentity,
            version: Self.version,
            archiveURL: Self.archiveURL,
            cachePath: nil,
            destinationPath: destinationPath,
            checksumAlgorithm: SHA256(),
            fingerprintStorage: nil,
            fingerprintCheckingMode: .strict,
            sourceURL: Self.sourceURL,
            authorizationProvider: TestAuthProvider(),
            progressHandler: nil,
            observabilityScope: observability.topScope
        )

        #expect(fileSystem.exists(destinationPath.appending(component: Manifest.filename)))
        let provider = try #require(capturedAuthProvider.get())
        let header = try #require(provider(Self.archiveURL))
        #expect(header.hasPrefix("Basic "))
    }

    // MARK: - Fingerprint storage error tests

    /// A fingerprint storage that throws a custom error on `get`.
    private struct ThrowingFingerprintStorage: PackageFingerprintStorage {
        let error: any Error

        func get(
            package: PackageIdentity,
            version: Version,
            observabilityScope: ObservabilityScope
        ) throws -> [Fingerprint.Kind: [Fingerprint.ContentType: Fingerprint]] {
            throw error
        }

        func put(
            package: PackageIdentity,
            version: Version,
            fingerprint: Fingerprint,
            observabilityScope: ObservabilityScope
        ) throws {}

        func get(
            package: PackageReference,
            version: Version,
            observabilityScope: ObservabilityScope
        ) throws -> [Fingerprint.Kind: [Fingerprint.ContentType: Fingerprint]] {
            throw error
        }

        func put(
            package: PackageReference,
            version: Version,
            fingerprint: Fingerprint,
            observabilityScope: ObservabilityScope
        ) throws {}
    }

    @Test("fingerprint storage get throwing non-notFound error propagates and emits diagnostic")
    func fingerprintStorageNonNotFoundError() async throws {
        let fileSystem = InMemoryFileSystem()
        let observability = ObservabilitySystem.makeForTesting()

        let downloader = SourceArchiveDownloader(
            httpClient: Self.mockHTTPClient(fileSystem: fileSystem),
            archiver: Self.mockArchiver(fileSystem: fileSystem),
            fileSystem: fileSystem
        )

        let destinationPath = AbsolutePath("/workspace/testpackage-storage-error")
        let storageError = StringError("database connection lost")

        await #expect(throws: StringError.self) {
            try await downloader.downloadSourceArchive(
                package: Self.packageIdentity,
                version: Self.version,
                archiveURL: Self.archiveURL,
                cachePath: nil,
                destinationPath: destinationPath,
                checksumAlgorithm: SHA256(),
                fingerprintStorage: ThrowingFingerprintStorage(error: storageError),
                fingerprintCheckingMode: .strict,
                sourceURL: Self.sourceURL,
                authorizationProvider: nil,
                progressHandler: nil,
                observabilityScope: observability.topScope
            )
        }

        #expect(observability.diagnostics.contains {
            $0.message.contains("failed to get source archive fingerprint")
        })
    }

    // MARK: - Cache path tests

    @Test
    func downloadWithCachePathCopiesFilesToCache() async throws {
        let fileSystem = InMemoryFileSystem()
        let observability = ObservabilitySystem.makeForTesting()

        let downloader = SourceArchiveDownloader(
            httpClient: Self.mockHTTPClient(fileSystem: fileSystem),
            archiver: Self.mockArchiver(fileSystem: fileSystem),
            fileSystem: fileSystem
        )

        let destinationPath = AbsolutePath("/workspace/testpackage-cachecopy")
        let cachePath = AbsolutePath("/cache/testpackage/1.0.0")

        try await Self.performDownload(
            downloader: downloader,
            destinationPath: destinationPath,
            cachePath: cachePath,
            observabilityScope: observability.topScope
        )

        // Verify both destination and cache have Package.swift
        #expect(fileSystem.exists(destinationPath.appending(component: Manifest.filename)))
        #expect(fileSystem.exists(cachePath.appending(component: Manifest.filename)))
    }

    // MARK: - Remove and re-fetch tests

    @Test("removing destination directory and re-downloading triggers a fresh fetch")
    func removeAndRefetch() async throws {
        let fileSystem = InMemoryFileSystem()
        let observability = ObservabilitySystem.makeForTesting()
        let downloadCount = ThreadSafeBox<Int>(0)

        let httpClient = HTTPClient { request, _ in
            switch request.kind {
            case .download(let fs, let destination):
                downloadCount.mutate { $0 += 1 }
                try fs.writeFileContents(destination, bytes: ByteString(Self.archiveContent))
                return .okay()
            case .generic:
                return .okay()
            }
        }

        let downloader = SourceArchiveDownloader(
            httpClient: httpClient,
            archiver: Self.mockArchiver(fileSystem: fileSystem),
            fileSystem: fileSystem
        )

        let destinationPath = AbsolutePath("/workspace/testpackage-refetch")

        // First download.
        try await Self.performDownload(
            downloader: downloader,
            destinationPath: destinationPath,
            observabilityScope: observability.topScope
        )
        #expect(fileSystem.exists(destinationPath.appending(component: Manifest.filename)))
        #expect(downloadCount.get() == 1)

        // Remove the destination.
        try fileSystem.removeFileTree(destinationPath)
        #expect(!fileSystem.exists(destinationPath))

        // Re-download — should fetch again.
        try await Self.performDownload(
            downloader: downloader,
            destinationPath: destinationPath,
            observabilityScope: observability.topScope
        )
        #expect(fileSystem.exists(destinationPath.appending(component: Manifest.filename)))
        #expect(downloadCount.get() == 2)
    }

    @Test("removing destination restores from cache without network fetch")
    func removeAndRestoreFromCache() async throws {
        let fileSystem = InMemoryFileSystem()
        let observability = ObservabilitySystem.makeForTesting()
        let downloadCount = ThreadSafeBox<Int>(0)

        let httpClient = HTTPClient { request, _ in
            switch request.kind {
            case .download(let fs, let destination):
                downloadCount.mutate { $0 += 1 }
                try fs.writeFileContents(destination, bytes: ByteString(Self.archiveContent))
                return .okay()
            case .generic:
                return .okay()
            }
        }

        let downloader = SourceArchiveDownloader(
            httpClient: httpClient,
            archiver: Self.mockArchiver(fileSystem: fileSystem),
            fileSystem: fileSystem
        )

        let destinationPath = AbsolutePath("/workspace/testpackage-cache-restore")
        let cachePath = AbsolutePath("/cache/testpackage/1.0.0")

        // First download — populates both destination and cache.
        try await Self.performDownload(
            downloader: downloader,
            destinationPath: destinationPath,
            cachePath: cachePath,
            observabilityScope: observability.topScope
        )
        #expect(downloadCount.get() == 1)
        #expect(fileSystem.exists(cachePath.appending(component: Manifest.filename)))

        // Remove destination only; cache stays.
        try fileSystem.removeFileTree(destinationPath)
        #expect(!fileSystem.exists(destinationPath))

        // Re-download — should restore from cache, NOT hit the network.
        let newDestination = AbsolutePath("/workspace/testpackage-cache-restore-2")
        try await Self.performDownload(
            downloader: downloader,
            destinationPath: newDestination,
            cachePath: cachePath,
            observabilityScope: observability.topScope
        )
        #expect(fileSystem.exists(newDestination.appending(component: Manifest.filename)))
        #expect(downloadCount.get() == 1, "should not have hit the network — cache provides the content")
    }
}
