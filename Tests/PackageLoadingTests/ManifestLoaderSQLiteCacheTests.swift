/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020-2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
@testable import PackageLoading
import PackageModel
import TSCBasic
import TSCTestSupport
import TSCUtility
import XCTest

class ManifestLoaderSQLiteCacheTests: XCTestCase {
    func testHappyCase() throws {
        try testWithTemporaryDirectory { tmpPath in
            let path = tmpPath.appending(component: "test.db")
            let storage = SQLiteBackedCache<ManifestLoader.ManifestParseResult>(tableName: "manifests", path: path)
            defer { XCTAssertNoThrow(try storage.close()) }

            let mockManifests = try makeMockManifests(fileSystem: localFileSystem, rootPath: tmpPath)
            try mockManifests.forEach { key, manifest in
                _ = try storage.put(key: key.sha256Checksum, value: manifest)
            }

            try mockManifests.forEach { key, manifest in
                let result = try storage.get(key: key.sha256Checksum)
                XCTAssertEqual(result?.parsedManifest, manifest.parsedManifest)
            }

            guard case .path(let storagePath) = storage.location else {
                return XCTFail("invalid location \(storage.location)")
            }

            XCTAssertTrue(storage.fileSystem.exists(storagePath), "expected file to be written")
        }
    }
}

private func makeMockManifests(fileSystem: FileSystem, rootPath: AbsolutePath, count: Int = Int.random(in: 50 ..< 100)) throws -> [ManifestLoader.ManifestCacheKey: ManifestLoader.ManifestParseResult] {
    var manifests = [ManifestLoader.ManifestCacheKey: ManifestLoader.ManifestParseResult]()
    for index in 0 ..< count {
        let manifestPath = rootPath.appending(components: "\(index)", "Package.swift")
        try fileSystem.writeFileContents(manifestPath) { stream in
            stream <<< """
            import PackageDescription
            let package = Package(
            name: "Trivial-\(index)",
                targets: [
                    .target(
                        name: "foo-\(index)",
                        dependencies: []),

            )
            """
        }
        let key = try ManifestLoader.ManifestCacheKey(packageIdentity: PackageIdentity(path: manifestPath),
                                                      manifestPath: manifestPath,
                                                      toolsVersion: ToolsVersion.currentToolsVersion,
                                                      env: [:],
                                                      swiftpmVersion: SwiftVersion.currentVersion.displayString,
                                                      fileSystem: fileSystem)
        manifests[key] = ManifestLoader.ManifestParseResult(compilerOutput: "mock-output-\(index)",
                                                            parsedManifest: "{ 'name': 'mock-manifest-\(index)' }")
    }

    return manifests
}
