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
import TSCBasic
import TSCTestSupport
import XCTest

class ManifestLoaderSQLiteCacheTests: XCTestCase {
    func testHappyCase() throws {
        try testWithTemporaryDirectory { tmpPath in
            let path = tmpPath.appending(component: "test.db")
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
}

private func makeMockManifests(fileSystem: FileSystem, rootPath: AbsolutePath, count: Int = Int.random(in: 50 ..< 100)) throws -> [ManifestLoader.CacheKey: ManifestLoader.EvaluationResult] {
    var manifests = [ManifestLoader.CacheKey: ManifestLoader.EvaluationResult]()
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
        let key = try ManifestLoader.CacheKey(packageIdentity: PackageIdentity(path: manifestPath),
                                              manifestPath: manifestPath,
                                              toolsVersion: ToolsVersion.current,
                                              env: [:],
                                              swiftpmVersion: SwiftVersion.current.displayString,
                                              fileSystem: fileSystem)
        manifests[key] = ManifestLoader.EvaluationResult(compilerOutput: "mock-output-\(index)",
                                                         manifestJSON: "{ 'name': 'mock-manifest-\(index)' }")
    }

    return manifests
}
