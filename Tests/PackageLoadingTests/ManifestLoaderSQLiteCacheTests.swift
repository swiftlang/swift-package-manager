/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
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
            let storage = SQLiteManifestCache(path: path)
            defer { XCTAssertNoThrow(try storage.close()) }


            let mockManifests = try makeMockManifests(fileSystem: localFileSystem, rootPath: tmpPath)
            try mockManifests.forEach { key, manifest in
                _ = try storage.put(key: key, manifest: manifest)
            }

            try mockManifests.forEach { key, manifest in
                let result = try storage.get(key: key)
                XCTAssertEqual(result?.parsedManifest, manifest.parsedManifest)
            }

            guard case .path(let storagePath) = storage.location else {
                return XCTFail("invalid location \(storage.location)")
            }

            XCTAssertTrue(storage.fileSystem.exists(storagePath), "expected file to be written")
        }
    }

    func testFileDeleted() throws {
        try testWithTemporaryDirectory { tmpPath in
            let path = tmpPath.appending(component: "test.db")
            let storage = SQLiteManifestCache(path: path)
            defer { XCTAssertNoThrow(try storage.close()) }

            let mockManifests = try makeMockManifests(fileSystem: localFileSystem, rootPath: tmpPath)
            try mockManifests.forEach {  key, manifest in
                _ = try storage.put(key: key, manifest: manifest)
            }

            try mockManifests.forEach { key, manifest in
                let result = try storage.get(key: key)
                XCTAssertEqual(result?.parsedManifest, manifest.parsedManifest)
            }

            guard case .path(let storagePath) = storage.location else {
                return XCTFail("invalid location \(storage.location)")
            }

            XCTAssertTrue(storage.fileSystem.exists(storagePath), "expected file to exist at \(storagePath)")
            try storage.fileSystem.removeFileTree(storagePath)

            do {
                let result = try storage.get(key: mockManifests.first!.key)
                XCTAssertNil(result)
            }

            do {
                XCTAssertNoThrow(try storage.put(key: mockManifests.first!.key, manifest: mockManifests.first!.value))
                let result = try storage.get(key: mockManifests.first!.key)
                XCTAssertEqual(result?.parsedManifest, mockManifests.first!.value.parsedManifest)
            }

            XCTAssertTrue(storage.fileSystem.exists(storagePath), "expected file to exist at \(storagePath)")
        }
    }

    func testFileCorrupt() throws {
        try testWithTemporaryDirectory { tmpPath in
            let path = tmpPath.appending(component: "test.db")
            let storage = SQLiteManifestCache(path: path)
            defer { XCTAssertNoThrow(try storage.close()) }

            let mockManifests = try makeMockManifests(fileSystem: localFileSystem, rootPath: tmpPath)
            try mockManifests.forEach {  key, manifest in
                _ = try storage.put(key: key, manifest: manifest)
            }

            try mockManifests.forEach { key, manifest in
                let result = try storage.get(key: key)
                XCTAssertEqual(result?.parsedManifest, manifest.parsedManifest)
            }

            guard case .path(let storagePath) = storage.location else {
                return XCTFail("invalid location \(storage.location)")
            }

            try storage.close()

            XCTAssertTrue(storage.fileSystem.exists(storagePath), "expected file to exist at \(path)")
            try storage.fileSystem.writeFileContents(storagePath, bytes: ByteString("blah".utf8))

            XCTAssertThrowsError(try storage.get(key: mockManifests.first!.key), "expected error", { error in
                XCTAssert("\(error)".contains("is not a database"), "Expected file is not a database error")
            })

            XCTAssertThrowsError(try storage.put(key: mockManifests.first!.key, manifest: mockManifests.first!.value), "expected error", { error in
                XCTAssert("\(error)".contains("is not a database"), "Expected file is not a database error")
            })
        }
    }

    func testMaxSizeNotHandled() throws {
        try testWithTemporaryDirectory { tmpPath in
            let path = tmpPath.appending(component: "test.db")
            var configuration = SQLiteManifestCache.Configuration()
            configuration.maxSizeInBytes = 1024 * 3
            configuration.truncateWhenFull = false
            let storage = SQLiteManifestCache(location: .path(path), configuration: configuration)
            defer { XCTAssertNoThrow(try storage.close()) }

            func create() throws {
                let mockManifests = try makeMockManifests(fileSystem: localFileSystem, rootPath: tmpPath, count: 50)
                try mockManifests.forEach {  key, manifest in
                    _ = try storage.put(key: key, manifest: manifest)
                }
            }

            XCTAssertThrowsError(try create(), "expected error", { error in
                XCTAssertEqual(error as? SQLite.Errors, .databaseFull, "Expected 'databaseFull' error")
            })
        }
    }

    func testMaxSizeHandled() throws {
        try testWithTemporaryDirectory { tmpPath in
            let path = tmpPath.appending(component: "test.db")
            var configuration = SQLiteManifestCache.Configuration()
            configuration.maxSizeInBytes = 1024 * 3
            configuration.truncateWhenFull = true
            let storage = SQLiteManifestCache(location: .path(path), configuration: configuration)
            defer { XCTAssertNoThrow(try storage.close()) }

            var keys = [ManifestLoader.ManifestCacheKey]()
            let mockManifests = try makeMockManifests(fileSystem: localFileSystem, rootPath: tmpPath, count: 50)
            try mockManifests.forEach { key, manifest in
                _ = try storage.put(key: key, manifest: manifest)
                keys.append(key)
            }

            do {
                let result = try storage.get(key: mockManifests.first!.key)
                XCTAssertNil(result)
            }

            do {
                let result = try storage.get(key: keys.last!)
                XCTAssertEqual(result?.parsedManifest, mockManifests[keys.last!]?.parsedManifest)
            }
        }
    }
}

fileprivate func makeMockManifests(fileSystem: FileSystem, rootPath: AbsolutePath, count: Int = Int.random(in: 50 ..< 100)) throws -> [ManifestLoader.ManifestCacheKey: ManifestLoader.ManifestParseResult] {
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
        let key = try ManifestLoader.ManifestCacheKey(packageIdentity: PackageIdentity.init(path: manifestPath),
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

