//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020-2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
@testable import PackageLoading
import PackageModel
import SPMTestSupport
import XCTest

class ManifestLoaderCacheTests: XCTestCase {
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

    func testInMemoryCache() throws {
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

        let manifestLoader = ManifestLoader(toolchain: try! UserToolchain.default, delegate: .none)

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
        let manifestPath = rootPath.appending(components: "\(index)", "Package.swift")

        try fileSystem.createDirectory(manifestPath.parentDirectory, recursive: true)
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
            packageIdentity: PackageIdentity(path: manifestPath),
            packageLocation: manifestPath.pathString,
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
