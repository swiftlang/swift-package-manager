//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
@testable import Basics
import TSCTestSupport
import Testing

struct FileSystemTests {
    @Test
    func stripFirstLevelComponent() throws {
        let fileSystem = InMemoryFileSystem()

        let rootPath = AbsolutePath("/root")
        try fileSystem.createDirectory(rootPath)

        let totalDirectories = Int.random(in: 0 ..< 100)
        for index in 0 ..< totalDirectories {
            let path = rootPath.appending("dir\(index)")
            try fileSystem.createDirectory(path, recursive: false)
        }

        let totalFiles = Int.random(in: 0 ..< 100)
        for index in 0 ..< totalFiles {
            let path = rootPath.appending("file\(index)")
            try fileSystem.writeFileContents(path, string: "\(index)")
        }

        do {
            let contents = try fileSystem.getDirectoryContents(.root)
            #expect(contents.count == 1)
        }

        try fileSystem.stripFirstLevel(of: .root)

        do {
            let contents = Set(try fileSystem.getDirectoryContents(.root))
            #expect(contents.count == totalDirectories + totalFiles)

            for index in 0 ..< totalDirectories {
                #expect(contents.contains("dir\(index)"))
            }
            for index in 0 ..< totalFiles {
                #expect(contents.contains("file\(index)"))
            }
        }
    }

    @Test
    func stripFirstLevelComponentErrors() throws {
        let functionUnderTest = "stripFirstLevel"
        do {
            let fileSystem = InMemoryFileSystem()
            #expect(throws: StringError("\(functionUnderTest) requires single top level directory")) {
                try fileSystem.stripFirstLevel(of: .root)
            }
        }

        do {
            let fileSystem = InMemoryFileSystem()
            for index in 0 ..< 3 {
                let path = AbsolutePath.root.appending("dir\(index)")
                try fileSystem.createDirectory(path, recursive: false)
            }
            #expect(throws: StringError("\(functionUnderTest) requires single top level directory")) {
                try fileSystem.stripFirstLevel(of: .root)
            }
        }

        do {
            let fileSystem = InMemoryFileSystem()
            for index in 0 ..< 3 {
                let path = AbsolutePath.root.appending("file\(index)")
                try fileSystem.writeFileContents(path, string: "\(index)")
            }
            #expect(throws: StringError("\(functionUnderTest) requires single top level directory")) {
                try fileSystem.stripFirstLevel(of: .root)
            }
        }

        do {
            let fileSystem = InMemoryFileSystem()
            let path = AbsolutePath.root.appending("file")
            try fileSystem.writeFileContents(path, string: "")
            #expect(throws: StringError("\(functionUnderTest) requires single top level directory")) {
                try fileSystem.stripFirstLevel(of: .root)
            }
        }
    }
}
