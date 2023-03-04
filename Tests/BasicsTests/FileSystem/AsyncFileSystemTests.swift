//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#if swift(>=5.5.2)
import _Concurrency

@testable import Basics
import TSCBasic
import XCTest
import TSCTestSupport

final class AsyncFileSystemTests: XCTestCase {
    func testStripFirstLevelComponent() async throws {
        let fileSystem = AsyncFileSystem { InMemoryFileSystem() }

        let rootPath = AbsolutePath("/root")
        try await fileSystem.createDirectory(rootPath)

        let totalDirectories = Int.random(in: 0 ..< 100)
        for index in 0 ..< totalDirectories {
            let path = rootPath.appending("dir\(index)")
            try await fileSystem.createDirectory(path, recursive: false)
        }

        let totalFiles = Int.random(in: 0 ..< 100)
        for index in 0 ..< totalFiles {
            let path = rootPath.appending("file\(index)")
            try await fileSystem.writeFileContents(path, string: "\(index)")
        }

        do {
            let contents = try await fileSystem.getDirectoryContents(.root)
            XCTAssertEqual(contents.count, 1)
        }

        try await fileSystem.stripFirstLevel(of: .root)

        do {
            let contents = Set(try await fileSystem.getDirectoryContents(.root))
            XCTAssertEqual(contents.count, totalDirectories + totalFiles)

            for index in 0 ..< totalDirectories {
                XCTAssertTrue(contents.contains("dir\(index)"))
            }
            for index in 0 ..< totalFiles {
                XCTAssertTrue(contents.contains("file\(index)"))
            }
        }
    }

    func testStripFirstLevelComponentErrors() async throws {
        do {
            let fileSystem = AsyncFileSystem { InMemoryFileSystem() }
            do {
                try await fileSystem.stripFirstLevel(of: .root)
                XCTFail("expected error")
            } catch {
                XCTAssertMatch((error as? StringError)?.description, .contains("requires single top level directory"))
            }
        }

        do {
            let fileSystem = AsyncFileSystem { InMemoryFileSystem() }
            for index in 0 ..< 3 {
                let path = AbsolutePath.root.appending("dir\(index)")
                try await fileSystem.createDirectory(path, recursive: false)
            }
            do {
                try await fileSystem.stripFirstLevel(of: .root)
                XCTFail("expected error")
            } catch {
                XCTAssertMatch((error as? StringError)?.description, .contains("requires single top level directory"))
            }
        }

        do {
            let fileSystem = AsyncFileSystem { InMemoryFileSystem() }
            for index in 0 ..< 3 {
                let path = AbsolutePath.root.appending("file\(index)")
                try await fileSystem.writeFileContents(path, string: "\(index)")
            }
            do {
                try await fileSystem.stripFirstLevel(of: .root)
                XCTFail("expected error")
            } catch {
                XCTAssertMatch((error as? StringError)?.description, .contains("requires single top level directory"))
            }
        }

        do {
            let fileSystem = AsyncFileSystem { InMemoryFileSystem() }
            let path = AbsolutePath.root.appending("file")
            try await fileSystem.writeFileContents(path, string: "")
            try await fileSystem.stripFirstLevel(of: .root)
            XCTFail("expected error")
        } catch {
            XCTAssertMatch((error as? StringError)?.description, .contains("requires single top level directory"))
        }
    }
}

#endif // swift(>=5.5.2)
