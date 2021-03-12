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

final class PackageCollectionsSourcesStorageTest: XCTestCase {
    func testHappyCase() throws {
        let mockFileSystem = InMemoryFileSystem()
        let storage = FilePackageCollectionsSourcesStorage(fileSystem: mockFileSystem)

        try assertHappyCase(storage: storage)

        let buffer = try mockFileSystem.readFileContents(storage.path)
        XCTAssertNotEqual(buffer.count, 0, "expected file to be written")
        print(buffer)
    }

    func testRealFile() throws {
        try testWithTemporaryDirectory { tmpPath in
            let fileSystem = localFileSystem
            let path = tmpPath.appending(component: "test.json")
            let storage = FilePackageCollectionsSourcesStorage(fileSystem: fileSystem, path: path)

            try assertHappyCase(storage: storage)

            let buffer = try fileSystem.readFileContents(storage.path)
            XCTAssertNotEqual(buffer.count, 0, "expected file to be written")
            print(buffer)
        }
    }

    func assertHappyCase(storage: PackageCollectionsSourcesStorage) throws {
        let sources = makeMockSources()

        try sources.forEach { source in
            _ = try tsc_await { callback in storage.add(source: source, order: nil, callback: callback) }
        }

        do {
            let list = try tsc_await { callback in storage.list(callback: callback) }
            XCTAssertEqual(list.count, sources.count, "sources should match")
        }

        let remove = sources.enumerated().filter { index, _ in index % 2 == 0 }.map { $1 }
        try remove.forEach { source in
            _ = try tsc_await { callback in storage.remove(source: source, callback: callback) }
        }

        do {
            let list = try tsc_await { callback in storage.list(callback: callback) }
            XCTAssertEqual(list.count, sources.count - remove.count, "sources should match")
        }

        let remaining = sources.filter { !remove.contains($0) }
        try sources.forEach { source in
            XCTAssertEqual(try tsc_await { callback in storage.exists(source: source, callback: callback) }, remaining.contains(source))
        }

        do {
            _ = try tsc_await { callback in storage.move(source: remaining.last!, to: 0, callback: callback) }
            let list = try tsc_await { callback in storage.list(callback: callback) }
            XCTAssertEqual(list.count, remaining.count, "sources should match")
            XCTAssertEqual(list.first, remaining.last, "item should match")
        }

        do {
            _ = try tsc_await { callback in storage.move(source: remaining.last!, to: remaining.count - 1, callback: callback) }
            let list = try tsc_await { callback in storage.list(callback: callback) }
            XCTAssertEqual(list.count, remaining.count, "sources should match")
            XCTAssertEqual(list.last, remaining.last, "item should match")
        }

        do {
            let list = try tsc_await { callback in storage.list(callback: callback) }
            var source = list.first!
            source.isTrusted = !(source.isTrusted ?? false)
            _ = try tsc_await { callback in storage.update(source: source, callback: callback) }
            let listAfter = try tsc_await { callback in storage.list(callback: callback) }
            XCTAssertEqual(source.isTrusted, listAfter.first!.isTrusted, "isTrusted should match")
        }

        do {
            let list = try tsc_await { callback in storage.list(callback: callback) }
            var source = list.first!
            source.skipSignatureCheck = !source.skipSignatureCheck
            _ = try tsc_await { callback in storage.update(source: source, callback: callback) }
            let listAfter = try tsc_await { callback in storage.list(callback: callback) }
            XCTAssertEqual(source.skipSignatureCheck, listAfter.first!.skipSignatureCheck, "skipSignatureCheck should match")
        }
    }

    func testFileDeleted() throws {
        let mockFileSystem = InMemoryFileSystem()
        let storage = FilePackageCollectionsSourcesStorage(fileSystem: mockFileSystem)

        let sources = makeMockSources()

        try sources.forEach { source in
            _ = try tsc_await { callback in storage.add(source: source, order: nil, callback: callback) }
        }

        do {
            let list = try tsc_await { callback in storage.list(callback: callback) }
            XCTAssertEqual(list.count, sources.count, "collections should match")
        }

        try mockFileSystem.removeFileTree(storage.path)
        XCTAssertFalse(mockFileSystem.exists(storage.path), "expected file to be deleted")

        do {
            let list = try tsc_await { callback in storage.list(callback: callback) }
            XCTAssertEqual(list.count, 0, "collections should match")
        }
    }

    func testFileEmpty() throws {
        let mockFileSystem = InMemoryFileSystem()
        let storage = FilePackageCollectionsSourcesStorage(fileSystem: mockFileSystem)

        let sources = makeMockSources()

        try sources.forEach { source in
            _ = try tsc_await { callback in storage.add(source: source, order: nil, callback: callback) }
        }

        do {
            let list = try tsc_await { callback in storage.list(callback: callback) }
            XCTAssertEqual(list.count, sources.count, "collections should match")
        }

        try mockFileSystem.writeFileContents(storage.path, bytes: ByteString("".utf8))
        let buffer = try mockFileSystem.readFileContents(storage.path)
        XCTAssertEqual(buffer.count, 0, "expected file to be empty")

        do {
            let list = try tsc_await { callback in storage.list(callback: callback) }
            XCTAssertEqual(list.count, 0, "collections should match")
        }
    }

    func testFileCorrupt() throws {
        let mockFileSystem = InMemoryFileSystem()
        let storage = FilePackageCollectionsSourcesStorage(fileSystem: mockFileSystem)

        let sources = makeMockSources()

        try sources.forEach { source in
            _ = try tsc_await { callback in storage.add(source: source, order: nil, callback: callback) }
        }

        let list = try tsc_await { callback in storage.list(callback: callback) }
        XCTAssertEqual(list.count, sources.count, "collections should match")

        try mockFileSystem.writeFileContents(storage.path, bytes: ByteString("{".utf8))

        let buffer = try mockFileSystem.readFileContents(storage.path)
        XCTAssertNotEqual(buffer.count, 0, "expected file to be written")
        print(buffer)

        XCTAssertThrowsError(try tsc_await { callback in storage.list(callback: callback) }, "expected an error", { error in
            XCTAssert(error is DecodingError, "expected error to match")
        })
    }
}
