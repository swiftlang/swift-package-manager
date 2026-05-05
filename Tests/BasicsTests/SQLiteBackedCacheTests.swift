//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Foundation

@testable import Basics
import _InternalTestSupport
import tsan_utils
import Testing

struct SQLiteBackedCacheTests {
    @Test
    func happyCase() throws {
        try testWithTemporaryDirectory { tmpPath in
            let path = tmpPath.appending("test.db")
            let cache = SQLiteBackedCache<String>(tableName: "SQLiteBackedCacheTest", path: path)
            defer {
                #expect(throws: Never.self) {
                    try cache.close()
                }
            }

            let mockData = try makeMockData(fileSystem: localFileSystem, rootPath: tmpPath)
            try mockData.forEach { key, value in
                _ = try cache.put(key: key, value: value)
            }

            try mockData.forEach { key, _ in
                let result = try cache.get(key: key)
                #expect(mockData[key] == result)
            }

            let key = mockData.first!.key

            _ = try cache.put(key: key, value: "foobar", replace: false)
            #expect(try cache.get(key: key) == mockData[key], "Actual is not as expected")

            _ = try cache.put(key: key, value: "foobar", replace: true)
            #expect(try cache.get(key: key) == "foobar", "Actual is not as expected")

            try cache.remove(key: key)
            #expect(try cache.get(key: key) == nil, "Actual is not as expected")

            guard case .path(let cachePath) = cache.location else {
                Issue.record("invalid location \(cache.location)")
                return
            }

            #expect(cache.fileSystem.exists(cachePath), "expected file to be written")
        }
    }

    @Test(
        .disabled(if: (ProcessInfo.hostOperatingSystem == .windows), "open file cannot be deleted on Windows"),
        .disabled(if: is_tsan_enabled(), "Disabling as tsan is enabled")
    )
    func fileDeleted() throws {
        try testWithTemporaryDirectory { tmpPath in
            let path = tmpPath.appending("test.db")
            let cache = SQLiteBackedCache<String>(tableName: "SQLiteBackedCacheTest", path: path)
            defer {
                #expect(throws: Never.self) {
                    try cache.close()
                }
            }

            let mockData = try makeMockData(fileSystem: localFileSystem, rootPath: tmpPath)
            try mockData.forEach { key, value in
                _ = try cache.put(key: key, value: value)
            }

            try mockData.forEach { key, _ in
                let result = try cache.get(key: key)
                #expect(mockData[key] == result)
            }

            guard case .path(let cachePath) = cache.location else {
                Issue.record("invalid location \(cache.location)")
                return
            }

            #expect(cache.fileSystem.exists(cachePath), "expected file to exist at \(cachePath)")
            try cache.fileSystem.removeFileTree(cachePath)

            let key = mockData.first!.key

            do {
                let result = try cache.get(key: key)
                #expect(result == nil)
            }

            do {
                #expect(throws: Never.self) {
                    try cache.put(key: key, value: mockData[key]!)
                }
                let result = try cache.get(key: key)
                #expect(mockData[key] == result)
            }

            #expect(cache.fileSystem.exists(cachePath), "expected file to exist at \(cachePath)")
        }
    }

    @Test(
        .disabled(if: is_tsan_enabled(), "Disabling as tsan is enabled")
    )
    func fileCorrupt() throws {

        try testWithTemporaryDirectory { tmpPath in
            let path = tmpPath.appending("test.db")
            let cache = SQLiteBackedCache<String>(tableName: "SQLiteBackedCacheTest", path: path)
            defer {
                #expect(throws: Never.self) {
                    try cache.close()
                }
            }

            let mockData = try makeMockData(fileSystem: localFileSystem, rootPath: tmpPath)
            try mockData.forEach { key, value in
                _ = try cache.put(key: key, value: value)
            }

            try mockData.forEach { key, _ in
                let result = try cache.get(key: key)
                #expect(mockData[key] == result)
            }

            guard case .path(let cachePath) = cache.location else {
                Issue.record("invalid location \(cache.location)")
                return
            }

            try cache.close()

            #expect(cache.fileSystem.exists(cachePath), "expected file to exist at \(path)")
            try cache.fileSystem.writeFileContents(cachePath, string: "blah")

            #expect {
                try cache.get(key: mockData.first!.key)
            } throws: { error in
                return "\(error)".contains("is not a database")
            }

            #expect {
                try cache.put(key: mockData.first!.key, value: mockData.first!.value)
            } throws: { error in
                return "\(error)".contains("is not a database")
            }
        }
    }

    @Test
    func maxSizeNotHandled() throws {
        try testWithTemporaryDirectory { tmpPath in
            let path = tmpPath.appending("test.db")
            var configuration = SQLiteBackedCacheConfiguration()
            configuration.maxSizeInBytes = 1024 * 3
            configuration.truncateWhenFull = false
            let cache = SQLiteBackedCache<String>(tableName: "SQLiteBackedCacheTest", path: path, configuration: configuration)
            defer {
                #expect(throws: Never.self) {
                    try cache.close()
                }
            }

            func create() throws {
                let mockData = try makeMockData(fileSystem: localFileSystem, rootPath: tmpPath, count: 500)
                try mockData.forEach { key, value in
                    _ = try cache.put(key: key, value: value)
                }
            }

            #expect {
                try create()
            } throws: { error in
                let error = try #require(error as? SQLite.Errors)
                return error == .databaseFull
            }
        }
    }

    @Test
    func maxSizeHandled() throws {
        try testWithTemporaryDirectory { tmpPath in
            let path = tmpPath.appending("test.db")
            var configuration = SQLiteBackedCacheConfiguration()
            configuration.maxSizeInBytes = 1024 * 3
            configuration.truncateWhenFull = true
            let cache = SQLiteBackedCache<String>(tableName: "SQLiteBackedCacheTest", path: path, configuration: configuration)
            defer {
                #expect(throws: Never.self) {
                    try cache.close()
                }
            }

            var keys = [String]()
            let mockData = try makeMockData(fileSystem: localFileSystem, rootPath: tmpPath, count: 500)
            try mockData.forEach { key, value in
                _ = try cache.put(key: key, value: value)
                keys.append(key)
            }

            do {
                let result = try cache.get(key: mockData.first!.key)
                #expect(result == nil)
            }

            do {
                let result = try cache.get(key: keys.last!)
                #expect(mockData[keys.last!] == result)
            }
        }
    }

    @Test
    func initialFileCreation() throws {
        try testWithTemporaryDirectory { tmpPath in
            let paths = [
                tmpPath.appending("foo", "test.db"),
                // Ensure it works recursively.
                tmpPath.appending("bar", "baz", "test.db"),
            ]

            for path in paths {
                let cache = SQLiteBackedCache<String>(tableName: "SQLiteBackedCacheTest", path: path)
                // Put an entry to ensure the file is created.
                #expect(throws: Never.self) {
                    try cache.put(key: "foo", value: "bar")
                }
                #expect(throws: Never.self) {
                    try cache.close()
                }
                #expect(localFileSystem.exists(path), "expected file to be created at \(path)")
            }
        }
    }
}

private func makeMockData(fileSystem: FileSystem, rootPath: AbsolutePath, count: Int = Int.random(in: 50..<100)) throws -> [String: String] {
    var data = [String: String]()
    let value = UUID().uuidString
    for index in 0..<count {
        data["\(index)"] = "\(index) \(value)"
    }
    return data
}
