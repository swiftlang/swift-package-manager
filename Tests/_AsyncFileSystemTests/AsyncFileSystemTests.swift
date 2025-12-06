//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

import _AsyncFileSystem
import _InternalTestSupport
import Testing
import struct SystemPackage.FilePath

struct AsyncFileSystemTests {
    @Test
    func mockFileSystem() async throws {
        let fs = MockFileSystem()

        let mockPath: FilePath = "/foo/bar"

        #expect(await !fs.exists(mockPath))

        let mockContent = "baz".utf8

        try await fs.write(mockPath, bytes: mockContent)

        #expect(await fs.exists(mockPath))

        // Test overwriting
        try await fs.write(mockPath, bytes: mockContent)

        #expect(await fs.exists(mockPath))

        let bytes = try await fs.withOpenReadableFile(mockPath) { fileHandle in
            try await fileHandle.read().reduce(into: []) { $0.append(contentsOf: $1) }
        }

        #expect(bytes == Array(mockContent))
    }
    @Test
    func oSFileSystem() async throws {
        try await testWithTemporaryDirectory { tmpDir in
            let fs = OSFileSystem()

            let mockPath = FilePath(tmpDir.appending("foo").pathString)

            #expect(await !fs.exists(mockPath))

            let mockContent = "baz".utf8

            try await fs.write(mockPath, bytes: mockContent)

            #expect(await fs.exists(mockPath))

            // Test overwriting
            try await fs.write(mockPath, bytes: mockContent)

            #expect(await fs.exists(mockPath))

            let bytes = try await fs.withOpenReadableFile(mockPath) { fileHandle in
                try await fileHandle.read().reduce(into: []) { $0.append(contentsOf: $1) }
            }

            #expect(bytes == Array(mockContent))
        }
    }
}
