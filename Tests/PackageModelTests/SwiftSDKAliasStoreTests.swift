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

import Basics
import Foundation
@_spi(SwiftPMInternal)
@testable import PackageModel
import _InternalTestSupport
import Testing

import struct TSCBasic.ByteString

// MARK: - Test Data

private let testIndexJSON = """
{
    "schemaVersion": "1.0",
    "remote": "https://download.swift.org/swift-sdk-aliases",
    "aliases": {
        "wasi": "wasi.jsonl",
        "static-linux": "static-linux.jsonl"
    }
}
"""

private let testShardJSONL = """
{ "swiftCompilerTag": "DEVELOPMENT-SNAPSHOT-2025-09-14-a", "checksum": "abc123", "url": "https://swift.org/wasi-sdk-latest.tar.gz", "id": "wasi-sdk-latest", "targetTriple": "wasm32-unknown-wasi" }
{ "swiftCompilerTag": "swift-6.1-RELEASE", "checksum": "def456", "url": "https://swift.org/wasi-sdk-6.1.tar.gz", "id": "wasi-sdk-6.1", "targetTriple": "wasm32-unknown-wasi" }
{ "swiftCompilerTag": "swiftlang-6.0.0.7.6", "checksum": "ghi789", "url": "https://swift.org/wasi-sdk-xcode.tar.gz", "id": "wasi-sdk-xcode", "targetTriple": "wasm32-unknown-wasi" }
"""

// MARK: - Helper

private let testSDKsDirectory = AbsolutePath("/sdks")

private func makeTestFileSystem() throws -> InMemoryFileSystem {
    let fs = InMemoryFileSystem()
    try fs.createDirectory(testSDKsDirectory, recursive: true)
    try fs.createDirectory(AbsolutePath(validating: "/tmp"), recursive: true)
    return fs
}

private func makeAliasStore(
    fileSystem: any FileSystem,
    swiftSDKsDirectory: AbsolutePath = testSDKsDirectory,
    observabilityScope: ObservabilityScope? = nil
) -> SwiftSDKAliasStore {
    SwiftSDKAliasStore(
        swiftSDKsDirectory: swiftSDKsDirectory,
        fileSystem: fileSystem,
        observabilityScope: observabilityScope ?? ObservabilitySystem.makeForTesting().topScope
    )
}

private func makeMockHTTPClient(
    indexJSON: String = testIndexJSON,
    shardJSONL: String = testShardJSONL
) -> HTTPClient {
    HTTPClient { request, _ in
        let url = request.url.absoluteString
        if url.hasSuffix("aliases.json") {
            return HTTPClientResponse(
                statusCode: 200,
                body: Data(indexJSON.utf8)
            )
        } else if url.hasSuffix(".jsonl") {
            return HTTPClientResponse(
                statusCode: 200,
                body: Data(shardJSONL.utf8)
            )
        } else {
            return HTTPClientResponse(statusCode: 404)
        }
    }
}

private func makeFailingHTTPClient() -> HTTPClient {
    HTTPClient { _, _ in
        throw StringError("Network unavailable")
    }
}

// MARK: - Tests

@Suite
struct SwiftSDKAliasStoreTests {

    // MARK: - Happy Path Resolution

    @Test
    func resolveAliasMatchingCompilerTag() async throws {
        let fs = try makeTestFileSystem()
        let store = makeAliasStore(fileSystem: fs)

        let resolved = try await store.resolve(
            alias: "wasi",
            swiftCompilerTag: "DEVELOPMENT-SNAPSHOT-2025-09-14-a",
            httpClient: makeMockHTTPClient()
        )

        #expect(resolved.url == "https://swift.org/wasi-sdk-latest.tar.gz")
        #expect(resolved.checksum == "abc123")
        #expect(resolved.id == "wasi-sdk-latest")
        #expect(resolved.targetTriple == "wasm32-unknown-wasi")
    }

    @Test("Resolve alias matches correct tag when not first entry")
    func resolveAliasMatchesCorrectTagNotFirst() async throws {
        let fs = try makeTestFileSystem()
        let store = makeAliasStore(fileSystem: fs)

        let resolved = try await store.resolve(
            alias: "wasi",
            swiftCompilerTag: "swift-6.1-RELEASE",
            httpClient: makeMockHTTPClient()
        )

        #expect(resolved.url == "https://swift.org/wasi-sdk-6.1.tar.gz")
        #expect(resolved.checksum == "def456")
        #expect(resolved.id == "wasi-sdk-6.1")
    }

    @Test("Resolve alias caches index locally")
    func resolveAliasCachesIndexLocally() async throws {
        let fs = try makeTestFileSystem()
        let store = makeAliasStore(fileSystem: fs)

        // First resolve — fetches from remote
        _ = try await store.resolve(
            alias: "wasi",
            swiftCompilerTag: "DEVELOPMENT-SNAPSHOT-2025-09-14-a",
            httpClient: makeMockHTTPClient()
        )

        // Verify cache exists
        let cachedIndexPath = testSDKsDirectory.appending(components: "aliases", "aliases.json")
        #expect(fs.isFile(cachedIndexPath))

        // Second resolve — remote fails, should succeed from cache
        let resolved = try await store.resolve(
            alias: "wasi",
            swiftCompilerTag: "DEVELOPMENT-SNAPSHOT-2025-09-14-a",
            httpClient: makeFailingHTTPClient()
        )

        #expect(resolved.id == "wasi-sdk-latest")
    }

    @Test("Resolve alias caches shard locally")
    func resolveAliasCachesShardLocally() async throws {
        let fs = try makeTestFileSystem()
        let store = makeAliasStore(fileSystem: fs)

        // First resolve — fetches from remote
        _ = try await store.resolve(
            alias: "wasi",
            swiftCompilerTag: "swift-6.1-RELEASE",
            httpClient: makeMockHTTPClient()
        )

        // Verify shard cache exists
        let cachedShardPath = testSDKsDirectory.appending(components: "aliases", "wasi.jsonl")
        #expect(fs.isFile(cachedShardPath))
    }

    // MARK: - Failure Cases

    @Test("Resolve unknown alias throws aliasNotFound")
    func resolveUnknownAliasThrowsAliasNotFound() async throws {
        let fs = try makeTestFileSystem()
        let store = makeAliasStore(fileSystem: fs)

        await #expect {
            try await store.resolve(
                alias: "nonexistent",
                swiftCompilerTag: "swift-6.1-RELEASE",
                httpClient: makeMockHTTPClient()
            )
        } throws: { error in
            guard let aliasError = error as? SwiftSDKAliasError else { return false }
            guard case .aliasNotFound(let name) = aliasError else { return false }
            return name == "nonexistent"
        }
    }

    @Test("Resolve with no matching compiler tag throws")
    func resolveNoMatchingCompilerTagThrows() async throws {
        let fs = try makeTestFileSystem()
        let store = makeAliasStore(fileSystem: fs)

        await #expect {
            try await store.resolve(
                alias: "wasi",
                swiftCompilerTag: "unknown-tag-999",
                httpClient: makeMockHTTPClient()
            )
        } throws: { error in
            guard let aliasError = error as? SwiftSDKAliasError else { return false }
            guard case .noMatchingToolchainVersion(let alias, let tag) = aliasError else { return false }
            return alias == "wasi" && tag == "unknown-tag-999"
        }
    }

    @Test("Resolve with remote unavailable and no cache throws")
    func resolveRemoteUnavailableNoCacheThrows() async throws {
        let fs = try makeTestFileSystem()
        let store = makeAliasStore(fileSystem: fs)

        await #expect {
            try await store.resolve(
                alias: "wasi",
                swiftCompilerTag: "swift-6.1-RELEASE",
                httpClient: makeFailingHTTPClient()
            )
        } throws: { error in
            guard let aliasError = error as? SwiftSDKAliasError else { return false }
            guard case .aliasRemoteUnavailable = aliasError else { return false }
            return true
        }
    }

    @Test("Resolve with remote unavailable falls back to cache")
    func resolveRemoteUnavailableFallsBackToCache() async throws {
        let fs = try makeTestFileSystem()
        let store = makeAliasStore(fileSystem: fs)

        // Populate cache
        _ = try await store.resolve(
            alias: "wasi",
            swiftCompilerTag: "swift-6.1-RELEASE",
            httpClient: makeMockHTTPClient()
        )

        // Now resolve with failing HTTP — should use cache
        let resolved = try await store.resolve(
            alias: "wasi",
            swiftCompilerTag: "swift-6.1-RELEASE",
            httpClient: makeFailingHTTPClient()
        )

        #expect(resolved.id == "wasi-sdk-6.1")
    }

    @Test("Resolve with empty shard throws")
    func resolveEmptyShardThrows() async throws {
        let fs = try makeTestFileSystem()
        let store = makeAliasStore(fileSystem: fs)

        let emptyShardClient = HTTPClient { request, _ in
            let url = request.url.absoluteString
            if url.hasSuffix("aliases.json") {
                return HTTPClientResponse(statusCode: 200, body: Data(testIndexJSON.utf8))
            } else if url.hasSuffix(".jsonl") {
                return HTTPClientResponse(statusCode: 200, body: Data("".utf8))
            }
            return HTTPClientResponse(statusCode: 404)
        }

        await #expect {
            try await store.resolve(
                alias: "wasi",
                swiftCompilerTag: "swift-6.1-RELEASE",
                httpClient: emptyShardClient
            )
        } throws: { error in
            guard let aliasError = error as? SwiftSDKAliasError else { return false }
            guard case .emptyShard(let alias) = aliasError else { return false }
            return alias == "wasi"
        }
    }

    @Test("Resolve shard with malformed lines skips them and finds valid match")
    func resolveShardWithMalformedLinesSkipsThem() async throws {
        let fs = try makeTestFileSystem()
        let system = ObservabilitySystem.makeForTesting()
        let store = makeAliasStore(fileSystem: fs, observabilityScope: system.topScope)

        let mixedShard = """
        this is not valid json
        { "swiftCompilerTag": "swift-6.1-RELEASE", "checksum": "good", "url": "https://example.com/sdk.tar.gz", "id": "valid-sdk" }
        { broken json
        """

        let mixedClient = HTTPClient { request, _ in
            let url = request.url.absoluteString
            if url.hasSuffix("aliases.json") {
                return HTTPClientResponse(statusCode: 200, body: Data(testIndexJSON.utf8))
            } else if url.hasSuffix(".jsonl") {
                return HTTPClientResponse(statusCode: 200, body: Data(mixedShard.utf8))
            }
            return HTTPClientResponse(statusCode: 404)
        }

        let resolved = try await store.resolve(
            alias: "wasi",
            swiftCompilerTag: "swift-6.1-RELEASE",
            httpClient: mixedClient
        )

        #expect(resolved.id == "valid-sdk")
        #expect(resolved.checksum == "good")
    }

    // MARK: - Remote Management

    @Test("Set remote persists to disk")
    func setRemotePersists() throws {
        let fs = try makeTestFileSystem()
        let store = makeAliasStore(fileSystem: fs)

        try store.setRemote("https://example.com/aliases")

        let cachedIndexPath = testSDKsDirectory.appending(components: "aliases", "aliases.json")
        #expect(fs.isFile(cachedIndexPath))

        let data: Data = try fs.readFileContents(cachedIndexPath)
        let index = try JSONDecoder.makeWithDefaults().decode(SwiftSDKAliasIndex.self, from: data)
        #expect(index.remote == "https://example.com/aliases")
    }

    @Test("Set remote creates aliases directory if needed")
    func setRemoteCreatesDirectoryIfNeeded() throws {
        let fs = try makeTestFileSystem()
        let aliasesDir = testSDKsDirectory.appending(component: "aliases")
        #expect(!fs.isDirectory(aliasesDir))

        let store = makeAliasStore(fileSystem: fs)
        try store.setRemote("https://example.com/aliases")

        #expect(fs.isDirectory(aliasesDir))
    }

    @Test("Set remote rejects HTTP URLs")
    func setRemoteRejectsHTTP() throws {
        let fs = try makeTestFileSystem()
        let store = makeAliasStore(fileSystem: fs)

        #expect {
            try store.setRemote("http://example.com/aliases")
        } throws: { error in
            guard let aliasError = error as? SwiftSDKAliasError else { return false }
            guard case .httpsRemoteRequired(let url) = aliasError else { return false }
            return url == "http://example.com/aliases"
        }
    }

    @Test("List aliases returns sorted names")
    func listAliasesReturnsAlphabeticalOrder() async throws {
        let fs = try makeTestFileSystem()
        let store = makeAliasStore(fileSystem: fs)

        let aliases = try await store.listAliases(httpClient: makeMockHTTPClient())
        #expect(aliases == ["static-linux", "wasi"])
    }

    @Test("List aliases with empty index returns empty array")
    func listAliasesEmptyIndex() async throws {
        let fs = try makeTestFileSystem()
        let store = makeAliasStore(fileSystem: fs)

        let emptyIndexJSON = """
        { "schemaVersion": "1.0", "aliases": {} }
        """

        let client = HTTPClient { request, _ in
            let url = request.url.absoluteString
            if url.hasSuffix("aliases.json") {
                return HTTPClientResponse(statusCode: 200, body: Data(emptyIndexJSON.utf8))
            }
            return HTTPClientResponse(statusCode: 404)
        }

        let aliases = try await store.listAliases(httpClient: client)
        #expect(aliases.isEmpty)
    }

    // MARK: - Compiler Tag Format Tests

    @Test("Resolve with development snapshot tag")
    func resolveWithDevelopmentSnapshotTag() async throws {
        let fs = try makeTestFileSystem()
        let store = makeAliasStore(fileSystem: fs)

        let resolved = try await store.resolve(
            alias: "wasi",
            swiftCompilerTag: "DEVELOPMENT-SNAPSHOT-2025-09-14-a",
            httpClient: makeMockHTTPClient()
        )
        #expect(resolved.id == "wasi-sdk-latest")
    }

    @Test("Resolve with release tag")
    func resolveWithReleaseTag() async throws {
        let fs = try makeTestFileSystem()
        let store = makeAliasStore(fileSystem: fs)

        let resolved = try await store.resolve(
            alias: "wasi",
            swiftCompilerTag: "swift-6.1-RELEASE",
            httpClient: makeMockHTTPClient()
        )
        #expect(resolved.id == "wasi-sdk-6.1")
    }

    @Test("Resolve with Xcode toolchain tag")
    func resolveWithXcodeToolchainTag() async throws {
        let fs = try makeTestFileSystem()
        let store = makeAliasStore(fileSystem: fs)

        let resolved = try await store.resolve(
            alias: "wasi",
            swiftCompilerTag: "swiftlang-6.0.0.7.6",
            httpClient: makeMockHTTPClient()
        )
        #expect(resolved.id == "wasi-sdk-xcode")
    }

    // MARK: - Schema Version Tests

    @Test("Reject unsupported major schema version")
    func rejectUnsupportedSchemaVersion() async throws {
        let fs = try makeTestFileSystem()
        let store = makeAliasStore(fileSystem: fs)

        let v2IndexJSON = """
        { "schemaVersion": "2.0", "aliases": {"wasi": "wasi.jsonl"} }
        """

        let client = HTTPClient { request, _ in
            if request.url.absoluteString.hasSuffix("aliases.json") {
                return HTTPClientResponse(statusCode: 200, body: Data(v2IndexJSON.utf8))
            }
            return HTTPClientResponse(statusCode: 404)
        }

        await #expect {
            try await store.resolve(
                alias: "wasi",
                swiftCompilerTag: "swift-6.1-RELEASE",
                httpClient: client
            )
        } throws: { error in
            guard let aliasError = error as? SwiftSDKAliasError else { return false }
            guard case .invalidAliasIndex(let reason) = aliasError else { return false }
            return reason.contains("Unsupported schema version")
        }
    }

    @Test("Accept compatible minor schema version bump")
    func acceptCompatibleMinorSchemaVersion() async throws {
        let fs = try makeTestFileSystem()
        let store = makeAliasStore(fileSystem: fs)

        let v11IndexJSON = """
        { "schemaVersion": "1.1", "aliases": {"wasi": "wasi.jsonl"} }
        """

        let client = HTTPClient { request, _ in
            let url = request.url.absoluteString
            if url.hasSuffix("aliases.json") {
                return HTTPClientResponse(statusCode: 200, body: Data(v11IndexJSON.utf8))
            } else if url.hasSuffix(".jsonl") {
                return HTTPClientResponse(statusCode: 200, body: Data(testShardJSONL.utf8))
            }
            return HTTPClientResponse(statusCode: 404)
        }

        let resolved = try await store.resolve(
            alias: "wasi",
            swiftCompilerTag: "swift-6.1-RELEASE",
            httpClient: client
        )
        #expect(resolved.id == "wasi-sdk-6.1")
    }

    // MARK: - Path Traversal Protection

    @Test("Reject shard filename with path traversal")
    func rejectShardFilenameWithPathTraversal() async throws {
        let fs = try makeTestFileSystem()
        let store = makeAliasStore(fileSystem: fs)

        let maliciousIndexJSON = """
        { "schemaVersion": "1.0", "aliases": {"wasi": "../../../etc/passwd"} }
        """

        let client = HTTPClient { request, _ in
            if request.url.absoluteString.hasSuffix("aliases.json") {
                return HTTPClientResponse(statusCode: 200, body: Data(maliciousIndexJSON.utf8))
            }
            return HTTPClientResponse(statusCode: 404)
        }

        await #expect {
            try await store.resolve(
                alias: "wasi",
                swiftCompilerTag: "swift-6.1-RELEASE",
                httpClient: client
            )
        } throws: { error in
            guard let aliasError = error as? SwiftSDKAliasError else { return false }
            guard case .invalidAliasIndex(let reason) = aliasError else { return false }
            return reason.contains("path separators")
        }
    }
}
