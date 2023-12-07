//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@testable import Basics
@testable import PackageLoading
import PackageModel
import SPMTestSupport
import XCTest

import class TSCBasic.InMemoryFileSystem
import enum TSCBasic.ProcessEnv
import func TSCTestSupport.withCustomEnv

class ManifestLoaderCacheTests: XCTestCase {
    func testDBCaching() throws {
        try testWithTemporaryDirectory { path in
            let fileSystem = localFileSystem
            let observability = ObservabilitySystem.makeForTesting()

            let manifestPath = path.appending(components: "pkg", "Package.swift")
            try fileSystem.createDirectory(manifestPath.parentDirectory, recursive: true)
            try fileSystem.writeFileContents(
                manifestPath,
                string: """
                    import PackageDescription
                    let package = Package(
                        name: "Trivial",
                        targets: [
                            .target(
                                name: "foo",
                                dependencies: []),
                        ]
                    )
                    """
            )

            let delegate = ManifestTestDelegate()

            let manifestLoader = ManifestLoader(
                toolchain: try UserToolchain.default,
                useInMemoryCache: false,
                cacheDir: path,
                delegate: delegate
            )

            func check(loader: ManifestLoader, expectCached: Bool) throws {
                delegate.clear()
                delegate.prepare(expectParsing: !expectCached)

                let manifest = try XCTUnwrap(loader.load(
                    manifestPath: manifestPath,
                    packageKind: .root(manifestPath.parentDirectory),
                    toolsVersion: .current,
                    fileSystem: fileSystem,
                    observabilityScope: observability.topScope
                ))

                XCTAssertNoDiagnostics(observability.diagnostics)
                XCTAssertEqual(try delegate.loaded(timeout: .now() + 1), [manifestPath])
                XCTAssertEqual(try delegate.parsed(timeout: .now() + 1).count, expectCached ? 0 : 1)
                XCTAssertEqual(manifest.displayName, "Trivial")
                XCTAssertEqual(manifest.targets[0].name, "foo")
            }

            try check(loader: manifestLoader, expectCached: false)
            for _ in 0..<2 {
                try check(loader: manifestLoader, expectCached: true)
            }

            try fileSystem.writeFileContents(
                manifestPath,
                string: """
                    import PackageDescription

                    let package = Package(
                        name: "Trivial",
                        targets: [
                            .target(
                                name: "foo",
                                dependencies: [  ]),
                        ]
                    )

                    """
            )

            try check(loader: manifestLoader, expectCached: false)
            for _ in 0..<2 {
                try check(loader: manifestLoader, expectCached: true)
            }

            let noCacheLoader = ManifestLoader(
                toolchain: try UserToolchain.default,
                useInMemoryCache: false,
                cacheDir: .none,
                delegate: delegate
            )
            for _ in 0..<2 {
                try check(loader: noCacheLoader, expectCached: false)
            }

            // Resetting the cache should allow us to remove the cache
            // directory without triggering assertions in sqlite.
            manifestLoader.purgeCache(observabilityScope: observability.topScope)
            XCTAssertNoDiagnostics(observability.diagnostics)
            try fileSystem.removeFileTree(path)
        }
    }

    func testInMemoryCaching() throws {
        let fileSystem = InMemoryFileSystem()
        let observability = ObservabilitySystem.makeForTesting()

        let manifestPath = AbsolutePath.root.appending(components: "pkg", "Package.swift")
        try fileSystem.createDirectory(manifestPath.parentDirectory, recursive: true)
        try fileSystem.writeFileContents(
            manifestPath,
            string: """
                import PackageDescription
                let package = Package(
                    name: "Trivial",
                    targets: [
                        .target(
                            name: "foo",
                            dependencies: []),
                    ]
                )
                """
        )

        let delegate = ManifestTestDelegate()

        let manifestLoader = ManifestLoader(
            toolchain: try UserToolchain.default,
            useInMemoryCache: true,
            cacheDir: .none,
            delegate: delegate
        )

        func check(loader: ManifestLoader, expectCached: Bool) throws {
            delegate.clear()
            delegate.prepare(expectParsing: !expectCached)

            let manifest = try XCTUnwrap(loader.load(
                manifestPath: manifestPath,
                packageKind: .root(manifestPath.parentDirectory),
                toolsVersion: .current,
                fileSystem: fileSystem,
                observabilityScope: observability.topScope
            ))

            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertEqual(try delegate.loaded(timeout: .now() + 1), [manifestPath])
            XCTAssertEqual(try delegate.parsed(timeout: .now() + 1).count, expectCached ? 0 : 1)
            XCTAssertEqual(manifest.displayName, "Trivial")
            XCTAssertEqual(manifest.targets[0].name, "foo")
        }

        try check(loader: manifestLoader, expectCached: false)
        for _ in 0..<2 {
            try check(loader: manifestLoader, expectCached: true)
        }

        try fileSystem.writeFileContents(
            manifestPath,
            string: """
                import PackageDescription

                let package = Package(
                    name: "Trivial",
                    targets: [
                        .target(
                            name: "foo",
                            dependencies: [  ]),
                    ]
                )

                """
        )

        try check(loader: manifestLoader, expectCached: false)
        for _ in 0..<2 {
            try check(loader: manifestLoader, expectCached: true)
        }

        let noCacheLoader = ManifestLoader(
            toolchain: try UserToolchain.default,
            useInMemoryCache: false,
            cacheDir: .none,
            delegate: delegate
        )
        for _ in 0..<2 {
            try check(loader: noCacheLoader, expectCached: false)
        }

        manifestLoader.purgeCache(observabilityScope: observability.topScope)
        XCTAssertNoDiagnostics(observability.diagnostics)
    }

    func testContentBasedCaching() throws {
        try testWithTemporaryDirectory { path in
            let manifest = """
                import PackageDescription
                let package = Package(
                    name: "Trivial",
                    targets: [
                        .target(name: "foo"),
                    ]
                )
            """

            let delegate = ManifestTestDelegate()

            let manifestLoader = ManifestLoader(
                toolchain: try UserToolchain.default,
                cacheDir: path,
                delegate: delegate
            )

            func check(loader: ManifestLoader, manifest: String) throws {
                let fileSystem = InMemoryFileSystem()
                let observability = ObservabilitySystem.makeForTesting()

                let manifestPath = AbsolutePath.root.appending(component: Manifest.filename)
                try fileSystem.writeFileContents(manifestPath, string: manifest)

                let m = try manifestLoader.load(
                    manifestPath: manifestPath,
                    packageKind: .root(.root),
                    toolsVersion: .current,
                    fileSystem: fileSystem,
                    observabilityScope: observability.topScope
                )

                XCTAssertNoDiagnostics(observability.diagnostics)
                XCTAssertEqual(m.displayName, "Trivial")
            }

            do {
                delegate.prepare()
                try check(loader: manifestLoader, manifest: manifest)
                XCTAssertEqual(try delegate.loaded(timeout: .now() + 1).count, 1)
                XCTAssertEqual(try delegate.parsed(timeout: .now() + 1).count, 1)
            }

            do {
                delegate.prepare(expectParsing: false)
                try check(loader: manifestLoader, manifest: manifest)
                XCTAssertEqual(try delegate.loaded(timeout: .now() + 1).count, 2)
                XCTAssertEqual(try delegate.parsed(timeout: .now() + 1).count, 1)
            }

            do {
                delegate.prepare()
                try check(loader: manifestLoader, manifest: manifest + "\n\n")
                XCTAssertEqual(try delegate.loaded(timeout: .now() + 1).count, 3)
                XCTAssertEqual(try delegate.parsed(timeout: .now() + 1).count, 2)
            }
        }
    }

    func testCacheInvalidationOnEnv() throws {
        try testWithTemporaryDirectory { path in
            let fileSystem = InMemoryFileSystem()
            let observability = ObservabilitySystem.makeForTesting()

            let manifestPath = path.appending(components: "pkg", "Package.swift")
            try fileSystem.createDirectory(manifestPath.parentDirectory, recursive: true)
            try fileSystem.writeFileContents(
                manifestPath,
                string: """
                    import PackageDescription
                    let package = Package(
                        name: "Trivial",
                        targets: [
                            .target(
                                name: "foo",
                                dependencies: []),
                        ]
                    )
                    """
            )

            let delegate = ManifestTestDelegate()

            let manifestLoader = ManifestLoader(
                toolchain: try UserToolchain.default,
                cacheDir: path,
                delegate: delegate
            )

            try check(loader: manifestLoader, expectCached: false)
            try check(loader: manifestLoader, expectCached: true)

            try withCustomEnv(["SWIFTPM_MANIFEST_CACHE_TEST": "1"]) {
                try check(loader: manifestLoader, expectCached: false)
                try check(loader: manifestLoader, expectCached: true)
            }

            try withCustomEnv(["SWIFTPM_MANIFEST_CACHE_TEST": "2"]) {
                try check(loader: manifestLoader, expectCached: false)
                try check(loader: manifestLoader, expectCached: true)
            }

            try check(loader: manifestLoader, expectCached: true)

            func check(loader: ManifestLoader, expectCached: Bool) throws {
                delegate.clear()
                delegate.prepare(expectParsing: !expectCached)

                let manifest = try XCTUnwrap(loader.load(
                    manifestPath: manifestPath,
                    packageKind: .root(manifestPath.parentDirectory),
                    toolsVersion: .current,
                    fileSystem: fileSystem,
                    observabilityScope: observability.topScope
                ))

                XCTAssertNoDiagnostics(observability.diagnostics)
                XCTAssertEqual(try delegate.loaded(timeout: .now() + 1), [manifestPath])
                XCTAssertEqual(try delegate.parsed(timeout: .now() + 1).count, expectCached ? 0 : 1)
                XCTAssertEqual(manifest.displayName, "Trivial")
                XCTAssertEqual(manifest.targets[0].name, "foo")
            }
        }
    }

    func testCacheDoNotInvalidationExpectedEnv() throws {
        try testWithTemporaryDirectory { path in
            let fileSystem = InMemoryFileSystem()
            let observability = ObservabilitySystem.makeForTesting()

            let manifestPath = path.appending(components: "pkg", "Package.swift")
            try fileSystem.createDirectory(manifestPath.parentDirectory, recursive: true)
            try fileSystem.writeFileContents(
                manifestPath,
                string: """
                    import PackageDescription
                    let package = Package(
                        name: "Trivial",
                        targets: [
                            .target(
                                name: "foo",
                                dependencies: []),
                        ]
                    )
                    """
            )

            let delegate = ManifestTestDelegate()

            let manifestLoader = ManifestLoader(
                toolchain: try UserToolchain.default,
                cacheDir: path,
                delegate: delegate
            )

            func check(loader: ManifestLoader, expectCached: Bool) throws {
                delegate.clear()
                delegate.prepare(expectParsing: !expectCached)

                let manifest = try XCTUnwrap(loader.load(
                    manifestPath: manifestPath,
                    packageKind: .root(manifestPath.parentDirectory),
                    toolsVersion: .current,
                    fileSystem: fileSystem,
                    observabilityScope: observability.topScope
                ))

                XCTAssertNoDiagnostics(observability.diagnostics)
                XCTAssertEqual(try delegate.loaded(timeout: .now() + 1), [manifestPath])
                XCTAssertEqual(try delegate.parsed(timeout: .now() + 1).count, expectCached ? 0 : 1)
                XCTAssertEqual(manifest.displayName, "Trivial")
                XCTAssertEqual(manifest.targets[0].name, "foo")
            }

            try check(loader: manifestLoader, expectCached: false)
            try check(loader: manifestLoader, expectCached: true)

            for key in EnvironmentVariables.nonCachableKeys {
                try withCustomEnv([key: UUID().uuidString]) {
                    try check(loader: manifestLoader, expectCached: true)
                }
            }

            try check(loader: manifestLoader, expectCached: true)
        }
    }

    func testSQLiteCacheHappyCase() throws {
        try testWithTemporaryDirectory { tmpPath in
            let path = tmpPath.appending("test.db")
            let storage = SQLiteBackedCache<ManifestLoader.EvaluationResult>(tableName: "manifests", path: path)
            defer { XCTAssertNoThrow(try storage.close()) }

            let mockManifests = try makeMockManifests(fileSystem: localFileSystem, rootPath: tmpPath)
            try mockManifests.forEach { key, manifest in
                _ = try storage.put(key: key.sha256Checksum, value: manifest)
            }

            try mockManifests.forEach { key, manifest in
                let result = try storage.get(key: key.sha256Checksum)
                XCTAssertEqual(result?.manifestJSON, manifest.manifestJSON)
            }

            guard case .path(let storagePath) = storage.location else {
                return XCTFail("invalid location \(storage.location)")
            }

            XCTAssertTrue(storage.fileSystem.exists(storagePath), "expected file to be written")
        }
    }

    func testInMemoryCacheHappyCase() throws {
        let content = """
            import PackageDescription
            let package = Package(
               name: "Root",
               dependencies: [
                   .package(url: "https://scm.com/foo", from: "1.0.0"),
                   .package(url: "https://scm.com/bar", from: "2.1.0")
               ]
            )
            """

        let manifestLoader = ManifestLoader(
            toolchain: try UserToolchain.default,
            cacheDir: .none,
            delegate: .none
        )

        let packageURL = "https://scm.com/\(UUID().uuidString)/foo"

        do {
            let observability = ObservabilitySystem.makeForTesting()
            let (manifest, validationDiagnostics) = try PackageDescriptionLoadingTests.loadAndValidateManifest(
                content,
                toolsVersion: .current,
                packageKind: .remoteSourceControl(.init(packageURL)),
                manifestLoader: manifestLoader,
                observabilityScope: observability.topScope
            )

            // first time should not come from cache
            testDiagnostics(observability.diagnostics, problemsOnly: false) { result in
                result.check(
                    diagnostic: .regex("evaluating manifest for .*"),
                    severity: .debug
                )
            }
            XCTAssertNoDiagnostics(validationDiagnostics)

            let deps = Dictionary(uniqueKeysWithValues: manifest.dependencies.map{ ($0.identity.description, $0) })
            XCTAssertEqual(deps["foo"], .remoteSourceControl(url: "https://scm.com/foo", requirement: .upToNextMajor(from: "1.0.0")))
            XCTAssertEqual(deps["bar"], .remoteSourceControl(url: "https://scm.com/bar", requirement: .upToNextMajor(from: "2.1.0")))
        }

        // second time should come from in-memory cache
        do {
            let observability = ObservabilitySystem.makeForTesting()
            let (manifest, validationDiagnostics) = try PackageDescriptionLoadingTests.loadAndValidateManifest(
                content,
                toolsVersion: .current,
                packageKind: .remoteSourceControl(.init(packageURL)),
                manifestLoader: manifestLoader,
                observabilityScope: observability.topScope
            )

            testDiagnostics(observability.diagnostics, problemsOnly: false) { result in
                result.check(
                    diagnostic: .regex("loading manifest .* from memory cache"),
                    severity: .debug
                )
            }
            XCTAssertNoDiagnostics(validationDiagnostics)

            let deps = Dictionary(uniqueKeysWithValues: manifest.dependencies.map{ ($0.identity.description, $0) })
            XCTAssertEqual(deps["foo"], .remoteSourceControl(url: "https://scm.com/foo", requirement: .upToNextMajor(from: "1.0.0")))
            XCTAssertEqual(deps["bar"], .remoteSourceControl(url: "https://scm.com/bar", requirement: .upToNextMajor(from: "2.1.0")))
        }

        // change location and make sure not coming from cache (rdar://73462555)
        let newPackageURL = "https://scm.com/\(UUID().uuidString)/foo"
        do {
            let observability = ObservabilitySystem.makeForTesting()
            let (manifest, validationDiagnostics) = try PackageDescriptionLoadingTests.loadAndValidateManifest(
                content,
                toolsVersion: .current,
                packageKind: .remoteSourceControl(.init(newPackageURL)),
                manifestLoader: manifestLoader,
                observabilityScope: observability.topScope
            )

            testDiagnostics(observability.diagnostics, problemsOnly: false) { result in
                result.check(
                    diagnostic: .regex("evaluating manifest for .*"),
                    severity: .debug
                )
            }
            XCTAssertNoDiagnostics(validationDiagnostics)

            let deps = Dictionary(uniqueKeysWithValues: manifest.dependencies.map{ ($0.identity.description, $0) })
            XCTAssertEqual(deps["foo"], .remoteSourceControl(url: "https://scm.com/foo", requirement: .upToNextMajor(from: "1.0.0")))
            XCTAssertEqual(deps["bar"], .remoteSourceControl(url: "https://scm.com/bar", requirement: .upToNextMajor(from: "2.1.0")))
        }

        // second time should come from in-memory cache
        do {
            let observability = ObservabilitySystem.makeForTesting()
            let (manifest, validationDiagnostics) = try PackageDescriptionLoadingTests.loadAndValidateManifest(
                content,
                toolsVersion: .current,
                packageKind: .remoteSourceControl(.init(newPackageURL)),
                manifestLoader: manifestLoader,
                observabilityScope: observability.topScope
            )

            testDiagnostics(observability.diagnostics, problemsOnly: false) { result in
                result.check(
                    diagnostic: .regex("loading manifest .* from memory cache"),
                    severity: .debug
                )
            }
            XCTAssertNoDiagnostics(validationDiagnostics)

            let deps = Dictionary(uniqueKeysWithValues: manifest.dependencies.map{ ($0.identity.description, $0) })
            XCTAssertEqual(deps["foo"], .remoteSourceControl(url: "https://scm.com/foo", requirement: .upToNextMajor(from: "1.0.0")))
            XCTAssertEqual(deps["bar"], .remoteSourceControl(url: "https://scm.com/bar", requirement: .upToNextMajor(from: "2.1.0")))
        }
    }
}

private func makeMockManifests(fileSystem: FileSystem, rootPath: AbsolutePath, count: Int = Int.random(in: 50 ..< 100)) throws -> [ManifestLoader.CacheKey: ManifestLoader.EvaluationResult] {
    var manifests = [ManifestLoader.CacheKey: ManifestLoader.EvaluationResult]()
    for index in 0 ..< count {
        let packagePath = rootPath.appending("\(index)")
        let manifestPath = packagePath.appending("Package.swift")

        try fileSystem.createDirectory(packagePath, recursive: true)
        try fileSystem.writeFileContents(
            manifestPath,
            string: """
            import PackageDescription
            let package = Package(
            name: "Trivial-\(index)",
                targets: [
                    .target(
                        name: "foo-\(index)",
                        dependencies: []),

            )
            """
        )
        let key = try ManifestLoader.CacheKey(
            packageIdentity: PackageIdentity(path: packagePath),
            packageLocation: packagePath.pathString,
            manifestPath: manifestPath,
            toolsVersion: ToolsVersion.current,
            env: [:],
            swiftpmVersion: SwiftVersion.current.displayString,
            fileSystem: fileSystem
        )
        manifests[key] = ManifestLoader.EvaluationResult(
            compilerOutput: "mock-output-\(index)",
            manifestJSON: "{ 'name': 'mock-manifest-\(index)' }"
        )
    }

    return manifests
}
