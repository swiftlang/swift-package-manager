//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import _Concurrency
import PackageModel
import PackageLoading
@testable import PackageRegistry
import _InternalTestSupport
import XCTest

import struct TSCUtility.Version

@available(macOS 15.0, *)
final class RegistryDownloadsManagerTests: XCTestCase {
    func testNoCache() async throws {
        let observability = ObservabilitySystem.makeForTesting()
        let fs = InMemoryFileSystem()

        let registry = MockRegistry(
            filesystem: fs,
            identityResolver: DefaultIdentityResolver(),
            checksumAlgorithm: MockHashAlgorithm(),
            fingerprintStorage: MockPackageFingerprintStorage(),
            signingEntityStorage: MockPackageSigningEntityStorage()
        )

        let package: PackageIdentity = .plain("test.\(UUID().uuidString)")
        let packageVersion: Version = "1.0.0"
        let packageSource = InMemoryRegistryPackageSource(fileSystem: fs, path: .root.appending(components: "registry", "server", package.description))
        try packageSource.writePackageContent()

        registry.addPackage(
            identity: package,
            versions: [packageVersion],
            source: packageSource
        )

        let delegate = MockRegistryDownloadsManagerDelegate()
        let downloadsPath = AbsolutePath.root.appending(components: "registry", "downloads")
        let manager = RegistryDownloadsManager(
            fileSystem: fs,
            path: downloadsPath,
            cachePath: .none, // cache disabled
            registryClient: registry.registryClient,
            delegate: delegate
        )

        // try to get a package

        do {
            await delegate.prepare(fetchExpected: true)
            let path = try await manager.lookup(package: package, version: packageVersion, observabilityScope: observability.topScope)
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertEqual(path, try downloadsPath.appending(package.downloadPath(version: packageVersion)))
            XCTAssertTrue(fs.isDirectory(path))

            await delegate.consume()
            await XCTAssertAsyncEqual(await delegate.willFetch.count, 1)
            await XCTAssertAsyncEqual(await delegate.willFetch.first?.packageVersion, .init(package: package, version: packageVersion))
            await XCTAssertAsyncEqual(await delegate.willFetch.first?.fetchDetails, .init(fromCache: false, updatedCache: false))

            await XCTAssertAsyncEqual(await delegate.didFetch.count, 1)
            await XCTAssertAsyncEqual(await delegate.didFetch.first?.packageVersion, .init(package: package, version: packageVersion))
            await XCTAssertAsyncEqual(try! await delegate.didFetch.first?.result.get(), .init(fromCache: false, updatedCache: false))
        }

        // try to get a package that does not exist

        let unknownPackage: PackageIdentity = .plain("unknown.\(UUID().uuidString)")
        let unknownPackageVersion: Version = "1.0.0"

        do {
            await delegate.prepare(fetchExpected: true)
            await XCTAssertAsyncThrowsError(try await manager.lookup(package: unknownPackage, version: unknownPackageVersion, observabilityScope: observability.topScope)) { error in
                XCTAssertNotNil(error as? RegistryError)
            }

            await delegate.consume()
            await XCTAssertAsyncEqual(await delegate.willFetch.map { ($0.packageVersion) },
                [
                    (PackageVersion(package: package, version: packageVersion)),
                    (PackageVersion(package: unknownPackage, version: unknownPackageVersion))
                ]
            )
            await XCTAssertAsyncEqual(await delegate.didFetch.map { ($0.packageVersion) },
                [
                    (PackageVersion(package: package, version: packageVersion)),
                    (PackageVersion(package: unknownPackage, version: unknownPackageVersion))
                ]
            )
        }

        // try to get the existing package again, no fetching expected this time

        do {
            await delegate.prepare(fetchExpected: false)
            let path = try await manager.lookup(package: package, version: packageVersion, observabilityScope: observability.topScope)
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertEqual(path, try downloadsPath.appending(package.downloadPath(version: packageVersion)))
            XCTAssertTrue(fs.isDirectory(path))

            await delegate.consume()
            await XCTAssertAsyncEqual(await delegate.willFetch.map { ($0.packageVersion) },
                [
                    (PackageVersion(package: package, version: packageVersion)),
                    (PackageVersion(package: unknownPackage, version: unknownPackageVersion))
                ]
            )
            await XCTAssertAsyncEqual(await delegate.didFetch.map { ($0.packageVersion) },
                [
                    (PackageVersion(package: package, version: packageVersion)),
                    (PackageVersion(package: unknownPackage, version: unknownPackageVersion))
                ]
            )
        }

        // remove the package

        do {
            try manager.remove(package: package)

            await delegate.prepare(fetchExpected: true)
            let path = try await manager.lookup(package: package, version: packageVersion, observabilityScope: observability.topScope)
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertEqual(path, try downloadsPath.appending(package.downloadPath(version: packageVersion)))
            XCTAssertTrue(fs.isDirectory(path))

            await delegate.consume()
            await XCTAssertAsyncEqual(
                await delegate.willFetch.map { ($0.packageVersion) },
                [
                    (PackageVersion(package: package, version: packageVersion)),
                    (PackageVersion(package: unknownPackage, version: unknownPackageVersion)),
                    (PackageVersion(package: package, version: packageVersion))
                ]
            )
            await XCTAssertAsyncEqual(
                await delegate.didFetch.map { ($0.packageVersion) },
                [
                    (PackageVersion(package: package, version: packageVersion)),
                    (PackageVersion(package: unknownPackage, version: unknownPackageVersion)),
                    (PackageVersion(package: package, version: packageVersion))
                ]
            )
        }
    }

    func testCache() async throws {
        let observability = ObservabilitySystem.makeForTesting()
        let fs = InMemoryFileSystem()

        let registry = MockRegistry(
            filesystem: fs,
            identityResolver: DefaultIdentityResolver(),
            checksumAlgorithm: MockHashAlgorithm(),
            fingerprintStorage: MockPackageFingerprintStorage(),
            signingEntityStorage: MockPackageSigningEntityStorage()
        )

        let package: PackageIdentity = .plain("test.\(UUID().uuidString)")
        let packageVersion: Version = "1.0.0"
        let packageSource = InMemoryRegistryPackageSource(
            fileSystem: fs,
            path: .root.appending(components: "registry", "server", package.description)
        )
        try packageSource.writePackageContent()

        registry.addPackage(
            identity: package,
            versions: [packageVersion],
            source: packageSource
        )

        let delegate = MockRegistryDownloadsManagerDelegate()
        let downloadsPath = AbsolutePath.root.appending(components: "registry", "downloads")
        let cachePath = AbsolutePath.root.appending(components: "registry", "cache")
        let manager = RegistryDownloadsManager(
            fileSystem: fs,
            path: downloadsPath,
            cachePath: cachePath, // cache enabled
            registryClient: registry.registryClient,
            delegate: delegate
        )

        // try to get a package

        do {
            await delegate.prepare(fetchExpected: true)
            let path = try await manager.lookup(package: package, version: packageVersion, observabilityScope: observability.topScope)
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertEqual(path, try downloadsPath.appending(package.downloadPath(version: packageVersion)))
            XCTAssertTrue(fs.isDirectory(path))
            XCTAssertTrue(
                fs.isDirectory(
                    cachePath.appending(components: package.registry!.scope.description, package.registry!.name.description, packageVersion.description)
                )
            )

            await delegate.consume()

            await XCTAssertAsyncEqual(await delegate.willFetch.count, 1)
            await XCTAssertAsyncEqual(await delegate.willFetch.first?.packageVersion, .init(package: package, version: packageVersion))
            await XCTAssertAsyncEqual(await delegate.willFetch.first?.fetchDetails, .init(fromCache: false, updatedCache: false))

            await XCTAssertAsyncEqual(await delegate.didFetch.count, 1)
            await XCTAssertAsyncEqual(await delegate.didFetch.first?.packageVersion, .init(package: package, version: packageVersion))
            await XCTAssertAsyncEqual(try! await delegate.didFetch.first?.result.get(), .init(fromCache: true, updatedCache: true))
        }

        // remove the "local" package, should come from cache

        do {
            try manager.remove(package: package)

            await delegate.prepare(fetchExpected: true)
            let path = try await manager.lookup(package: package, version: packageVersion, observabilityScope: observability.topScope)
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertEqual(path, try downloadsPath.appending(package.downloadPath(version: packageVersion)))
            XCTAssertTrue(fs.isDirectory(path))

            await delegate.consume()

            await XCTAssertAsyncEqual(await delegate.willFetch.count, 2)
            await XCTAssertAsyncEqual(await delegate.willFetch.last?.packageVersion, .init(package: package, version: packageVersion))
            await XCTAssertAsyncEqual(await delegate.willFetch.last?.fetchDetails, .init(fromCache: true, updatedCache: false))

            await XCTAssertAsyncEqual(await delegate.didFetch.count, 2)
            await XCTAssertAsyncEqual(await delegate.didFetch.last?.packageVersion, .init(package: package, version: packageVersion))
            await XCTAssertAsyncEqual(try! await delegate.didFetch.last?.result.get(), .init(fromCache: true, updatedCache: false))
        }

        // remove the "local" package, and purge cache

        do {
            try manager.remove(package: package)
            manager.purgeCache(observabilityScope: observability.topScope)

            await delegate.prepare(fetchExpected: true)
            let path = try await manager.lookup(package: package, version: packageVersion, observabilityScope: observability.topScope)
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertEqual(path, try downloadsPath.appending(package.downloadPath(version: packageVersion)))
            XCTAssertTrue(fs.isDirectory(path))

            await delegate.consume()

            await XCTAssertAsyncEqual(await delegate.willFetch.count, 3)
            await XCTAssertAsyncEqual(await delegate.willFetch.last?.packageVersion, .init(package: package, version: packageVersion))
            await XCTAssertAsyncEqual(await delegate.willFetch.last?.fetchDetails, .init(fromCache: false, updatedCache: false))

            await XCTAssertAsyncEqual(await delegate.didFetch.count, 3)
            await XCTAssertAsyncEqual(await delegate.didFetch.last?.packageVersion, .init(package: package, version: packageVersion))
            await XCTAssertAsyncEqual(try! await delegate.didFetch.last?.result.get(), .init(fromCache: true, updatedCache: true))
        }
    }

    func testConcurrency() async throws {
        let observability = ObservabilitySystem.makeForTesting()
        let fs = InMemoryFileSystem()

        let registry = MockRegistry(
            filesystem: fs,
            identityResolver: DefaultIdentityResolver(),
            checksumAlgorithm: MockHashAlgorithm(),
            fingerprintStorage: MockPackageFingerprintStorage(),
            signingEntityStorage: MockPackageSigningEntityStorage()
        )

        let downloadsPath = AbsolutePath.root.appending(components: "registry", "downloads")
        let delegate = MockRegistryDownloadsManagerDelegate()
        let manager = RegistryDownloadsManager(
            fileSystem: fs,
            path: downloadsPath,
            cachePath: .none, // cache disabled
            registryClient: registry.registryClient,
            delegate: delegate
        )

        // many different versions

        do {
            let concurrency = 100
            let package: PackageIdentity = .plain("test.\(UUID().uuidString)")
            let packageVersions = (0 ..< concurrency).map { Version($0, 0 , 0) }
            let packageSource = InMemoryRegistryPackageSource(
                fileSystem: fs,
                path: .root.appending(components: "registry", "server", package.description)
            )
            try packageSource.writePackageContent()

            registry.addPackage(
                identity: package,
                versions: packageVersions,
                source: packageSource
            )

            let results = try await withThrowingTaskGroup(of: (Version, AbsolutePath).self) { group in
                for packageVersion in packageVersions {
                    group.addTask {
                        await delegate.prepare(fetchExpected: true)
                        return (packageVersion, try await manager.lookup(
                            package: package,
                            version: packageVersion,
                            observabilityScope: observability.topScope
                        ))
                    }
                }

                return try await group.reduce(into: [:]) {
                    $0[$1.0] = $1.1
                }
            }

            await delegate.consume()
            await XCTAssertAsyncEqual(await delegate.willFetch.count, concurrency)
            await XCTAssertAsyncEqual(await delegate.didFetch.count, concurrency)

            XCTAssertEqual(results.count, concurrency)
            for packageVersion in packageVersions {
                let expectedPath = try downloadsPath.appending(package.downloadPath(version: packageVersion))
                XCTAssertEqual(results[packageVersion], expectedPath)
            }
        }

        // same versions

        do {
            let concurrency = 1000
            let repeatRatio = 10
            let package: PackageIdentity = .plain("test.\(UUID().uuidString)")
            let packageVersions = (0 ..< concurrency / 10).map { Version($0, 0 , 0) }
            let packageSource = InMemoryRegistryPackageSource(
                fileSystem: fs,
                path: .root.appending(components: "registry", "server", package.description)
            )
            try packageSource.writePackageContent()

            registry.addPackage(
                identity: package,
                versions: packageVersions,
                source: packageSource
            )

            await delegate.reset()
            let results = try await withThrowingTaskGroup(of: (Version, AbsolutePath).self) { group in
                for index in 0 ..< concurrency {
                    group.addTask {
                        await delegate.prepare(fetchExpected: index < concurrency / repeatRatio)
                        let packageVersion = Version(index % (concurrency / repeatRatio), 0, 0)
                        return (packageVersion, try await manager.lookup(
                            package: package,
                            version: packageVersion,
                            observabilityScope: observability.topScope
                        ))
                    }
                }

                return try await group.reduce(into: [:]) { $0[$1.0] = $1.1 }
            }

            await delegate.consume()
            await XCTAssertAsyncEqual(await delegate.willFetch.count, concurrency / repeatRatio)
            await XCTAssertAsyncEqual(await delegate.didFetch.count, concurrency / repeatRatio)

            XCTAssertEqual(results.count, concurrency / repeatRatio)
            for packageVersion in packageVersions {
                let expectedPath = try downloadsPath.appending(package.downloadPath(version: packageVersion))
                XCTAssertEqual(results[packageVersion], expectedPath)
            }
        }
    }
}

@available(macOS 15.0, *)
private actor MockRegistryDownloadsManagerDelegate: RegistryDownloadsManagerDelegate {
    typealias WillFetch = (packageVersion: PackageVersion, fetchDetails: RegistryDownloadsManager.FetchDetails)
    typealias DidFetch = (packageVersion: PackageVersion, result: Result<RegistryDownloadsManager.FetchDetails, Error>)

    private(set) var willFetch = [WillFetch]()
    private(set) var didFetch = [DidFetch]()

    private var expectedFetches = 0

    private nonisolated let willFetchContinuation: AsyncStream<WillFetch>.Continuation
    private let willFetchStream: AsyncStream<WillFetch>
    #if compiler(>=6.0)
    private var willFetchIterator: any AsyncIteratorProtocol<WillFetch, Never>
    #else
    private var willFetchIterator: any AsyncIteratorProtocol<WillFetch>
    #endif

    private nonisolated let didFetchContinuation: AsyncStream<DidFetch>.Continuation
    private let didFetchStream: AsyncStream<DidFetch>
    #if compiler(>=6.0)
    private var didFetchIterator: any AsyncIteratorProtocol<DidFetch, Never>
    #else
    private var didFetchIterator: any AsyncIteratorProtocol<DidFetch>
    #endif

    init() {
        (willFetchStream, willFetchContinuation) = AsyncStream.makeStream()
        self.willFetchIterator = willFetchStream.makeAsyncIterator()

        (didFetchStream, didFetchContinuation) = AsyncStream.makeStream()
        self.didFetchIterator = didFetchStream.makeAsyncIterator()
    }

    func prepare(fetchExpected: Bool) {
        if fetchExpected {
            expectedFetches += 1
        }
    }

    func consume() async {
        var elementsToFetch = expectedFetches

        while elementsToFetch > 0, let element = await self.willFetchIterator.next(isolation: #isolation) {
            self.willFetch.append(element)
            elementsToFetch -= 1
        }

        elementsToFetch = expectedFetches
        while elementsToFetch > 0, let element = await self.didFetchIterator.next(isolation: #isolation) {
            self.didFetch.append(element)
            elementsToFetch -= 1
        }

        expectedFetches = 0
    }

    func reset() {
        self.willFetch = []
        self.didFetch = []
    }

    nonisolated func willFetch(package: PackageIdentity, version: Version, fetchDetails: RegistryDownloadsManager.FetchDetails) {
        willFetchContinuation.yield((PackageVersion(package: package, version: version), fetchDetails: fetchDetails))
    }

    nonisolated func didFetch(package: PackageIdentity, version: Version, result: Result<RegistryDownloadsManager.FetchDetails, Error>, duration: DispatchTimeInterval) {
        didFetchContinuation.yield((PackageVersion(package: package, version: version), result: result))
    }

    nonisolated func fetching(package: PackageIdentity, version: Version, bytesDownloaded downloaded: Int64, totalBytesToDownload total: Int64?) {
    }
}

fileprivate struct PackageVersion: Hashable, Equatable {
    let package: PackageIdentity
    let version: Version
}
