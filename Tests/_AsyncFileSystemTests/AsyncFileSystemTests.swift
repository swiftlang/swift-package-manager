/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2024 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import _AsyncFileSystem
import _InternalTestSupport
import XCTest
import struct SystemPackage.FilePath

final class AsyncFileSystemTests: XCTestCase {
    func testMockFileSystem() async throws {
        let fs = MockFileSystem()

        let mockPath: FilePath = "/foo/bar"

        await XCTAssertAsyncFalse(await fs.exists(mockPath))

        let mockContent = "baz".utf8

        try await fs.write(mockPath, bytes: mockContent)

        await XCTAssertAsyncTrue(await fs.exists(mockPath))

        // Test overwriting
        try await fs.write(mockPath, bytes: mockContent)

        await XCTAssertAsyncTrue(await fs.exists(mockPath))

        let bytes = try await fs.withOpenReadableFile(mockPath) { fileHandle in
            try await fileHandle.read().reduce(into: []) { $0.append(contentsOf: $1) }
        }

        XCTAssertEqual(bytes, Array(mockContent))
    }
    func testOSFileSystem() async throws {
        try await testWithTemporaryDirectory { tmpDir in
            let fs = OSFileSystem()

            let mockPath = FilePath(tmpDir.appending("foo").pathString)

            await XCTAssertAsyncFalse(await fs.exists(mockPath))

            let mockContent = "baz".utf8

            try await fs.write(mockPath, bytes: mockContent)

            await XCTAssertAsyncTrue(await fs.exists(mockPath))

            // Test overwriting
            try await fs.write(mockPath, bytes: mockContent)

            await XCTAssertAsyncTrue(await fs.exists(mockPath))

            let bytes = try await fs.withOpenReadableFile(mockPath) { fileHandle in
                try await fileHandle.read().reduce(into: []) { $0.append(contentsOf: $1) }
            }

            XCTAssertEqual(bytes, Array(mockContent))
        }
    }
}
