/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

@testable import PackageCollections
import TSCBasic
import TSCTestSupport
import XCTest

final class PackageCollectionProfileStorageTest: XCTestCase {
    func testHappyCase() throws {
        let mockFileSystem = InMemoryFileSystem()
        let storage = FilePackageCollectionsProfileStorage(fileSystem: mockFileSystem)

        try assertHappyCase(storage: storage)

        let buffer = try mockFileSystem.readFileContents(storage.path)
        XCTAssertNotEqual(buffer.count, 0, "expected file to be written")
        print(buffer)
    }

    func testRealFile() throws {
        try testWithTemporaryDirectory { tmpPath in
            let fileSystem = localFileSystem
            let path = tmpPath.appending(component: "test.json")
            let storage = FilePackageCollectionsProfileStorage(fileSystem: fileSystem, path: path)

            try assertHappyCase(storage: storage)

            let buffer = try fileSystem.readFileContents(storage.path)
            XCTAssertNotEqual(buffer.count, 0, "expected file to be written")
            print(buffer)
        }
    }

    func assertHappyCase(storage: PackageCollectionsProfileStorage) throws {
        let sources = makeMockSources()

        try sources.forEach { source in
            _ = try tsc_await { callback in storage.add(source: source, order: nil, to: .default, callback: callback) }
        }

        let profiles = try tsc_await { callback in storage.listProfiles(callback: callback) }
        XCTAssertEqual(profiles.count, 1, "profiles should match")

        do {
            let list = try tsc_await { callback in storage.listSources(in: .default, callback: callback) }
            XCTAssertEqual(list.count, sources.count, "collections should match")
        }

        let remove = sources.enumerated().filter { index, _ in index % 2 == 0 }.map { $1 }
        try remove.forEach { source in
            _ = try tsc_await { callback in storage.remove(source: source, from: .default, callback: callback) }
        }

        do {
            let list = try tsc_await { callback in storage.listSources(in: .default, callback: callback) }
            XCTAssertEqual(list.count, sources.count - remove.count, "collections should match")
        }

        let remaining = sources.filter { !remove.contains($0) }
        try sources.forEach { source in
            XCTAssertEqual(try tsc_await { callback in storage.exists(source: source, in: .default, callback: callback) }, remaining.contains(source))
            XCTAssertEqual(try tsc_await { callback in storage.exists(source: source, in: nil, callback: callback) }, remaining.contains(source))
        }

        do {
            _ = try tsc_await { callback in storage.move(source: remaining.last!, to: 0, in: .default, callback: callback) }
            let list = try tsc_await { callback in storage.listSources(in: .default, callback: callback) }
            XCTAssertEqual(list.count, remaining.count, "collections should match")
            XCTAssertEqual(list.first, remaining.last, "item should match")
        }

        do {
            _ = try tsc_await { callback in storage.move(source: remaining.last!, to: remaining.count - 1, in: .default, callback: callback) }
            let list = try tsc_await { callback in storage.listSources(in: .default, callback: callback) }
            XCTAssertEqual(list.count, remaining.count, "collections should match")
            XCTAssertEqual(list.last, remaining.last, "item should match")
        }
    }

    func testFileDeleted() throws {
        let mockFileSystem = InMemoryFileSystem()
        let storage = FilePackageCollectionsProfileStorage(fileSystem: mockFileSystem)

        let sources = makeMockSources()

        try sources.forEach { source in
            _ = try tsc_await { callback in storage.add(source: source, order: nil, to: .default, callback: callback) }
        }

        do {
            let list = try tsc_await { callback in storage.listSources(in: .default, callback: callback) }
            XCTAssertEqual(list.count, sources.count, "collections should match")
        }

        try mockFileSystem.removeFileTree(storage.path)
        XCTAssertFalse(mockFileSystem.exists(storage.path), "expected file to be deleted")

        do {
            let list = try tsc_await { callback in storage.listSources(in: .default, callback: callback) }
            XCTAssertEqual(list.count, 0, "collections should match")
        }
    }

    func testFileEmpty() throws {
        let mockFileSystem = InMemoryFileSystem()
        let storage = FilePackageCollectionsProfileStorage(fileSystem: mockFileSystem)

        let sources = makeMockSources()

        try sources.forEach { source in
            _ = try tsc_await { callback in storage.add(source: source, order: nil, to: .default, callback: callback) }
        }

        do {
            let list = try tsc_await { callback in storage.listSources(in: .default, callback: callback) }
            XCTAssertEqual(list.count, sources.count, "collections should match")
        }

        try mockFileSystem.writeFileContents(storage.path, bytes: ByteString("".utf8))
        let buffer = try mockFileSystem.readFileContents(storage.path)
        XCTAssertEqual(buffer.count, 0, "expected file to be empty")

        do {
            let list = try tsc_await { callback in storage.listSources(in: .default, callback: callback) }
            XCTAssertEqual(list.count, 0, "collections should match")
        }
    }

    func testFileCorrupt() throws {
        let mockFileSystem = InMemoryFileSystem()
        let storage = FilePackageCollectionsProfileStorage(fileSystem: mockFileSystem)

        let sources = makeMockSources()

        try sources.forEach { source in
            _ = try tsc_await { callback in storage.add(source: source, order: nil, to: .default, callback: callback) }
        }

        let list = try tsc_await { callback in storage.listSources(in: .default, callback: callback) }
        XCTAssertEqual(list.count, sources.count, "collections should match")

        try mockFileSystem.writeFileContents(storage.path, bytes: ByteString("{".utf8))

        let buffer = try mockFileSystem.readFileContents(storage.path)
        XCTAssertNotEqual(buffer.count, 0, "expected file to be written")
        print(buffer)

        XCTAssertThrowsError(try tsc_await { callback in storage.listSources(in: .default, callback: callback) }, "expected an error", { error in
            XCTAssert(error is DecodingError, "expected error to match")
        })
    }

    func testCustomProfile() throws {
        let mockFileSystem = InMemoryFileSystem()
        let storage = FilePackageCollectionsProfileStorage(fileSystem: mockFileSystem)

        let profile = PackageCollectionsModel.Profile(name: "profile-\(UUID().uuidString)")
        let sources = makeMockSources()

        try sources.forEach { source in
            _ = try tsc_await { callback in storage.add(source: source, order: nil, to: profile, callback: callback) }
        }

        let profiles = try tsc_await { callback in storage.listProfiles(callback: callback) }
        XCTAssertEqual(profiles.count, 1, "profiles should match")

        do {
            let list = try tsc_await { callback in storage.listSources(in: profile, callback: callback) }
            XCTAssertEqual(list.count, sources.count, "sources should match")
        }

        let remove = sources.enumerated().filter { index, _ in index % 2 == 0 }.map { $1 }
        try remove.forEach { source in
            _ = try tsc_await { callback in storage.remove(source: source, from: profile, callback: callback) }
        }

        do {
            let list = try tsc_await { callback in storage.listSources(in: profile, callback: callback) }
            XCTAssertEqual(list.count, sources.count - remove.count, "sources should match")
        }

        try sources.forEach { source in
            XCTAssertEqual(try tsc_await { callback in storage.exists(source: source, in: profile, callback: callback) }, !remove.contains(source))
            XCTAssertEqual(try tsc_await { callback in storage.exists(source: source, in: nil, callback: callback) }, !remove.contains(source))
        }

        let buffer = try mockFileSystem.readFileContents(storage.path)
        XCTAssertNotEqual(buffer.count, 0, "expected file to be written")
        print(buffer)
    }

    func testMultipleProfiles() throws {
        let mockFileSystem = InMemoryFileSystem()
        let storage = FilePackageCollectionsProfileStorage(fileSystem: mockFileSystem)

        let sources = makeMockSources()
        var profiles = [PackageCollectionsModel.Profile(name: "profile-\(UUID().uuidString)"): [PackageCollectionsModel.PackageCollectionSource](),
                        PackageCollectionsModel.Profile(name: "profile-\(UUID().uuidString)"): [PackageCollectionsModel.PackageCollectionSource]()]

        try sources.enumerated().forEach { index, source in
            let profile = index % 2 == 0 ? Array(profiles.keys)[0] : Array(profiles.keys)[1]
            _ = try tsc_await { callback in storage.add(source: source, order: nil, to: profile, callback: callback) }
            profiles[profile]?.append(source)
        }

        let list = try tsc_await { callback in storage.listProfiles(callback: callback) }
        XCTAssertEqual(list.count, profiles.count, "list count should match")

        try profiles.forEach { profile, profileCollections in
            let list = try tsc_await { callback in storage.listSources(in: profile, callback: callback) }
            XCTAssertEqual(list.count, profileCollections.count, "list count should match")
        }

        let buffer = try mockFileSystem.readFileContents(storage.path)
        XCTAssertNotEqual(buffer.count, 0, "expected file to be written")
        print(buffer)
    }
}
