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
            delegate.prepare(fetchExpected: true)
            let path = try await manager.lookup(package: package, version: packageVersion, observabilityScope: observability.topScope)
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertEqual(path, try downloadsPath.appending(manager.storagePath(for: package, version: packageVersion)))
            XCTAssertTrue(fs.isDirectory(path))

            try delegate.wait(timeout: .now() + 2)
            XCTAssertEqual(delegate.willFetch.count, 1)
            XCTAssertEqual(delegate.willFetch.first?.packageVersion, .init(package: package, version: packageVersion))
            XCTAssertEqual(delegate.willFetch.first?.fetchDetails, .init(fromCache: false, updatedCache: false))

            XCTAssertEqual(delegate.didFetch.count, 1)
            XCTAssertEqual(delegate.didFetch.first?.packageVersion, .init(package: package, version: packageVersion))
            XCTAssertEqual(try! delegate.didFetch.first?.result.get(), .init(fromCache: false, updatedCache: false))
        }

        // try to get a package that does not exist

        let unknownPackage: PackageIdentity = .plain("unknown.\(UUID().uuidString)")
        let unknownPackageVersion: Version = "1.0.0"

        do {
            delegate.prepare(fetchExpected: true)
            await XCTAssertAsyncThrowsError(try await manager.lookup(package: unknownPackage, version: unknownPackageVersion, observabilityScope: observability.topScope)) { error in
                XCTAssertNotNil(error as? RegistryError)
            }

            try delegate.wait(timeout: .now() + 2)
            XCTAssertEqual(delegate.willFetch.map { ($0.packageVersion) },
                           [
                            (PackageVersion(package: package, version: packageVersion)),
                            (PackageVersion(package: unknownPackage, version: unknownPackageVersion))
                           ]
            )
            XCTAssertEqual(delegate.didFetch.map { ($0.packageVersion) },
                           [
                            (PackageVersion(package: package, version: packageVersion)),
                            (PackageVersion(package: unknownPackage, version: unknownPackageVersion))
                           ]
            )
        }

        // try to get the existing package again, no fetching expected this time

        do {
            delegate.prepare(fetchExpected: false)
            let path = try await manager.lookup(package: package, version: packageVersion, observabilityScope: observability.topScope)
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertEqual(path, try downloadsPath.appending(manager.storagePath(for: package, version: packageVersion)))
            XCTAssertTrue(fs.isDirectory(path))

            try delegate.wait(timeout: .now() + 2)
            XCTAssertEqual(delegate.willFetch.map { ($0.packageVersion) },
                           [
                            (PackageVersion(package: package, version: packageVersion)),
                            (PackageVersion(package: unknownPackage, version: unknownPackageVersion))
                           ]
            )
            XCTAssertEqual(delegate.didFetch.map { ($0.packageVersion) },
                           [
                            (PackageVersion(package: package, version: packageVersion)),
                            (PackageVersion(package: unknownPackage, version: unknownPackageVersion))
                           ]
            )
        }

        // remove the package

        do {
            try manager.remove(package: package)

            delegate.prepare(fetchExpected: true)
            let path = try await manager.lookup(package: package, version: packageVersion, observabilityScope: observability.topScope)
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertEqual(path, try downloadsPath.appending(manager.storagePath(for: package, version: packageVersion)))
            XCTAssertTrue(fs.isDirectory(path))

            try delegate.wait(timeout: .now() + 2)
            XCTAssertEqual(delegate.willFetch.map { ($0.packageVersion) },
                           [
                            (PackageVersion(package: package, version: packageVersion)),
                            (PackageVersion(package: unknownPackage, version: unknownPackageVersion)),
                            (PackageVersion(package: package, version: packageVersion))
                           ]
            )
            XCTAssertEqual(delegate.didFetch.map { ($0.packageVersion) },
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
        let packageSource = InMemoryRegistryPackageSource(fileSystem: fs, path: .root.appending(components: "registry", "server", package.description))
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
            delegate.prepare(fetchExpected: true)
            let path = try await manager.lookup(package: package, version: packageVersion, observabilityScope: observability.topScope)
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertEqual(path, try downloadsPath.appending(manager.storagePath(for: package, version: packageVersion)))
            XCTAssertTrue(fs.isDirectory(path))
            XCTAssertTrue(fs.isDirectory(try cachePath
                .appending(manager.storagePath(for: package, version: packageVersion))))

            try delegate.wait(timeout: .now() + 2)

            XCTAssertEqual(delegate.willFetch.count, 1)
            XCTAssertEqual(delegate.willFetch.first?.packageVersion, .init(package: package, version: packageVersion))
            XCTAssertEqual(delegate.willFetch.first?.fetchDetails, .init(fromCache: false, updatedCache: false))

            XCTAssertEqual(delegate.didFetch.count, 1)
            XCTAssertEqual(delegate.didFetch.first?.packageVersion, .init(package: package, version: packageVersion))
            XCTAssertEqual(try! delegate.didFetch.first?.result.get(), .init(fromCache: true, updatedCache: true))
        }

        // remove the "local" package, should come from cache

        do {
            try manager.remove(package: package)

            delegate.prepare(fetchExpected: true)
            let path = try await manager.lookup(package: package, version: packageVersion, observabilityScope: observability.topScope)
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertEqual(path, try downloadsPath.appending(manager.storagePath(for: package, version: packageVersion)))
            XCTAssertTrue(fs.isDirectory(path))

            try delegate.wait(timeout: .now() + 2)

            XCTAssertEqual(delegate.willFetch.count, 2)
            XCTAssertEqual(delegate.willFetch.last?.packageVersion, .init(package: package, version: packageVersion))
            XCTAssertEqual(delegate.willFetch.last?.fetchDetails, .init(fromCache: true, updatedCache: false))

            XCTAssertEqual(delegate.didFetch.count, 2)
            XCTAssertEqual(delegate.didFetch.last?.packageVersion, .init(package: package, version: packageVersion))
            XCTAssertEqual(try! delegate.didFetch.last?.result.get(), .init(fromCache: true, updatedCache: false))
        }

        // remove the "local" package, and purge cache

        do {
            try manager.remove(package: package)
            manager.purgeCache(observabilityScope: observability.topScope)

            delegate.prepare(fetchExpected: true)
            let path = try await manager.lookup(package: package, version: packageVersion, observabilityScope: observability.topScope)
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertEqual(path, try downloadsPath.appending(manager.storagePath(for: package, version: packageVersion)))
            XCTAssertTrue(fs.isDirectory(path))

            try delegate.wait(timeout: .now() + 2)

            XCTAssertEqual(delegate.willFetch.count, 3)
            XCTAssertEqual(delegate.willFetch.last?.packageVersion, .init(package: package, version: packageVersion))
            XCTAssertEqual(delegate.willFetch.last?.fetchDetails, .init(fromCache: false, updatedCache: false))

            XCTAssertEqual(delegate.didFetch.count, 3)
            XCTAssertEqual(delegate.didFetch.last?.packageVersion, .init(package: package, version: packageVersion))
            XCTAssertEqual(try! delegate.didFetch.last?.result.get(), .init(fromCache: true, updatedCache: true))
        }
    }

    func testStorageIsScopedToRegistry() async throws {
        let fs = InMemoryFileSystem()
        let package: PackageIdentity = .plain("test.\(UUID().uuidString)")
        let downloadsPath = AbsolutePath.root.appending(components: "registry", "downloads")
        let cachePath = AbsolutePath.root.appending(components: "registry", "cache")

        let first = try MockRegistryFixture(
            fileSystem: fs,
            name: "first",
            target: "FromFirstRegistry",
            downloadsPath: downloadsPath,
            cachePath: cachePath,
            package: package
        )
        let second = try MockRegistryFixture(
            fileSystem: fs,
            name: "second",
            target: "FromSecondRegistry",
            downloadsPath: downloadsPath,
            cachePath: cachePath,
            package: package
        )

        let firstObservability = ObservabilitySystem.makeForTesting()
        let firstPath = try await first.lookup(observabilityScope: firstObservability.topScope)
        XCTAssertNoDiagnostics(firstObservability.diagnostics)
        XCTAssertTrue(fs.exists(firstPath.appending(components: "Sources", "FromFirstRegistry", "file.swift")))

        let secondObservability = ObservabilitySystem.makeForTesting()
        let secondPath = try await second.lookup(observabilityScope: secondObservability.topScope)
        XCTAssertNoDiagnostics(secondObservability.diagnostics)

        // the second registry gets its own tree rather than reusing the first registry's
        XCTAssertNotEqual(firstPath, secondPath)
        XCTAssertTrue(fs.exists(secondPath.appending(components: "Sources", "FromSecondRegistry", "file.swift")))
        XCTAssertFalse(fs.exists(secondPath.appending(components: "Sources", "FromFirstRegistry", "file.swift")))

        try second.delegate.wait(timeout: .now() + 2)
        XCTAssertEqual(try! second.delegate.didFetch.last?.result.get(), .init(fromCache: true, updatedCache: true))

        let firstCachedPath = try first.cachedPackagePath()
        let secondCachedPath = try second.cachedPackagePath()
        XCTAssertTrue(fs.isDirectory(firstCachedPath))
        XCTAssertTrue(fs.isDirectory(secondCachedPath))
        XCTAssertNotEqual(firstCachedPath, secondCachedPath)
    }

    func testStorageKeyIsCanonicalized() throws {
        let key = { (url: String) in
            Registry(url: URL(url), supportsAvailability: false).storageKey
        }

        XCTAssertTrue(key("http://localhost/registry").hasPrefix("localhost-"))
        XCTAssertEqual(key("http://localhost/registry"), key("http://localhost/registry/"))
        XCTAssertEqual(key("http://localhost/registry"), key("http://LOCALHOST/Registry"))
        XCTAssertNotEqual(key("http://localhost/registry"), key("https://localhost/registry"))
        XCTAssertNotEqual(key("http://localhost/registry"), key("http://localhost/other"))

        // a host too long to label with stays under the path length limits
        let longHost = String(repeating: "a", count: 250)
        XCTAssertEqual(key("http://\(longHost)").utf8.count, 8)
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
            let packageSource = InMemoryRegistryPackageSource(fileSystem: fs, path: .root.appending(components: "registry", "server", package.description))
            try packageSource.writePackageContent()

            registry.addPackage(
                identity: package,
                versions: packageVersions,
                source: packageSource
            )

            let results = ThreadSafeKeyValueStore<Version, AbsolutePath>()
            try await withThrowingTaskGroup(of: Void.self) { group in
                for packageVersion in packageVersions {
                    group.addTask {
                        delegate.prepare(fetchExpected: true)
                        results[packageVersion] = try await manager.lookup(package: package, version: packageVersion, observabilityScope: observability.topScope)
                    }
                }
                try await group.waitForAll()
            }

            try delegate.wait(timeout: .now() + 2)
            XCTAssertEqual(delegate.willFetch.count, concurrency)
            XCTAssertEqual(delegate.didFetch.count, concurrency)

            XCTAssertEqual(results.count, concurrency)
            for packageVersion in packageVersions {
                let expectedPath = try downloadsPath.appending(manager.storagePath(for: package, version: packageVersion))
                XCTAssertEqual(results[packageVersion], expectedPath)
            }
        }

        // same versions

        do {
            let concurrency = 1000
            let repeatRatio = 10
            let package: PackageIdentity = .plain("test.\(UUID().uuidString)")
            let packageVersions = (0 ..< concurrency / 10).map { Version($0, 0 , 0) }
            let packageSource = InMemoryRegistryPackageSource(fileSystem: fs, path: .root.appending(components: "registry", "server", package.description))
            try packageSource.writePackageContent()

            registry.addPackage(
                identity: package,
                versions: packageVersions,
                source: packageSource
            )

            delegate.reset()
            let results = ThreadSafeKeyValueStore<Version, AbsolutePath>()
            try await withThrowingTaskGroup(of: Void.self) { group in
                for index in 0 ..< concurrency {
                    group.addTask {
                        delegate.prepare(fetchExpected: index < concurrency / repeatRatio)
                        let packageVersion = Version(index % (concurrency / repeatRatio), 0 , 0)
                        results[packageVersion] = try await manager.lookup(package: package, version: packageVersion, observabilityScope: observability.topScope)
                    }
                }
                try await group.waitForAll()
            }

            try delegate.wait(timeout: .now() + 2)
            XCTAssertEqual(delegate.willFetch.count, concurrency / repeatRatio)
            XCTAssertEqual(delegate.didFetch.count, concurrency / repeatRatio)

            XCTAssertEqual(results.count, concurrency / repeatRatio)
            for packageVersion in packageVersions {
                let expectedPath = try downloadsPath.appending(manager.storagePath(for: package, version: packageVersion))
                XCTAssertEqual(results[packageVersion], expectedPath)
            }
        }
    }
}

private final class MockRegistryDownloadsManagerDelegate: RegistryDownloadsManagerDelegate, @unchecked Sendable {
    private var _willFetch = [(packageVersion: PackageVersion, fetchDetails: RegistryDownloadsManager.FetchDetails)]()
    private var _didFetch = [(packageVersion: PackageVersion, result: Result<RegistryDownloadsManager.FetchDetails, Error>)]()

    private let lock = NSLock()
    private var group = DispatchGroup()

    public func prepare(fetchExpected: Bool) {
        if fetchExpected {
            group.enter() // will fetch
            group.enter() // did fetch
        }
    }

    public func reset() {
        self.group = DispatchGroup()
        self._willFetch = []
        self._didFetch = []
    }

    public func wait(timeout: DispatchTime) throws {
        switch group.wait(timeout: timeout) {
        case .success:
            return
        case .timedOut:
            throw StringError("timeout")
        }
    }

    var willFetch: [(packageVersion: PackageVersion, fetchDetails: RegistryDownloadsManager.FetchDetails)] {
        return self.lock.withLock { _willFetch }
    }

    var didFetch: [(packageVersion: PackageVersion, result: Result<RegistryDownloadsManager.FetchDetails, Error>)] {
        return self.lock.withLock { _didFetch }
    }

    func willFetch(package: PackageIdentity, version: Version, fetchDetails: RegistryDownloadsManager.FetchDetails) {
        self.lock.withLock {
            _willFetch += [(PackageVersion(package: package, version: version), fetchDetails: fetchDetails)]
        }
        self.group.leave()
    }

    func didFetch(package: PackageIdentity, version: Version, result: Result<RegistryDownloadsManager.FetchDetails, Error>, duration: DispatchTimeInterval) {
        self.lock.withLock {
            _didFetch += [(PackageVersion(package: package, version: version), result: result)]
        }
        self.group.leave()
    }

    func fetching(package: PackageIdentity, version: Version, bytesDownloaded downloaded: Int64, totalBytesToDownload total: Int64?) {
    }
}

fileprivate struct PackageVersion: Hashable, Equatable, Sendable {
    let package: PackageIdentity
    let version: Version
}

private struct MockRegistryFixture {
    let delegate: MockRegistryDownloadsManagerDelegate
    let manager: RegistryDownloadsManager

    private let package: PackageIdentity
    private let version: Version
    private let cachePath: AbsolutePath?

    init(
        fileSystem: InMemoryFileSystem,
        name: String,
        target: String,
        downloadsPath: AbsolutePath,
        cachePath: AbsolutePath?,
        package: PackageIdentity = .plain("test.\(UUID().uuidString)"),
        version: Version = "1.0.0"
    ) throws {
        let registry = MockRegistry(
            filesystem: fileSystem,
            identityResolver: DefaultIdentityResolver(),
            checksumAlgorithm: MockHashAlgorithm(),
            fingerprintStorage: MockPackageFingerprintStorage(),
            signingEntityStorage: MockPackageSigningEntityStorage(),
            customBaseURL: URL("http://localhost/registry/\(name)")
        )

        let source = InMemoryRegistryPackageSource(
            fileSystem: fileSystem,
            path: .root.appending(components: "registry", name, "server", package.description)
        )
        try source.writePackageContent(targets: [target])
        registry.addPackage(identity: package, versions: [version], source: source)

        self.package = package
        self.version = version
        self.cachePath = cachePath
        self.delegate = MockRegistryDownloadsManagerDelegate()
        self.manager = RegistryDownloadsManager(
            fileSystem: fileSystem,
            path: downloadsPath,
            cachePath: cachePath,
            registryClient: registry.registryClient,
            delegate: self.delegate
        )
    }

    func lookup(observabilityScope: ObservabilityScope) async throws -> AbsolutePath {
        self.delegate.prepare(fetchExpected: true)
        return try await self.manager.lookup(
            package: self.package,
            version: self.version,
            observabilityScope: observabilityScope
        )
    }

    func cachedPackagePath() throws -> AbsolutePath {
        try XCTUnwrap(self.cachePath)
            .appending(self.manager.storagePath(for: self.package, version: self.version))
    }
}
