/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2024 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

#if canImport(Testing)

import _AsyncFileSystem
import Testing
import struct SystemPackage.FilePath

@Test
func testMockFileSystem() async throws {
    let fs = MockFileSystem()

    let mockPath: FilePath = "/foo/bar"

    #expect(await !fs.exists(mockPath))

    let mockContent = "baz".utf8

    try await fs.write(mockPath, bytes: "baz".utf8)

    #expect(await fs.exists(mockPath))

    let bytes = try await fs.withOpenReadableFile(mockPath) { fileHandle in
        try await fileHandle.read().reduce(into: []) { $0.append(contentsOf: $1) }
    }

    #expect(bytes == Array(mockContent))
}

#endif
