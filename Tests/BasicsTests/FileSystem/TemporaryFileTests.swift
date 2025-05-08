//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Foundation

import Testing

import Basics

struct TemporaryAsyncFileTests {
    @Test
    func basicTemporaryDirectory() async throws {
        let path1: AbsolutePath = try await withTemporaryDirectory(removeTreeOnDeinit: true) { tempDirPath in
            // Do some async task
            try await Task.sleep(nanoseconds: 1_000)

            #expect(localFileSystem.isDirectory(tempDirPath))
            return tempDirPath
        }.value
        #expect(!localFileSystem.isDirectory(path1))

        // Test temp directory is not removed when its not empty.
        let path2: AbsolutePath = try await withTemporaryDirectory { tempDirPath in
            #expect(localFileSystem.isDirectory(tempDirPath))
            // Create a file inside the temp directory.
            let filePath = tempDirPath.appending("somefile")
            // Do some async task
            try await Task.sleep(nanoseconds: 1_000)

            try localFileSystem.writeFileContents(filePath, bytes: [])
            return tempDirPath
        }.value
        #expect(localFileSystem.isDirectory(path2))
        // Cleanup.
        try localFileSystem.removeFileTree(path2)
        #expect(!localFileSystem.isDirectory(path2))

        // Test temp directory is removed when its not empty and removeTreeOnDeinit is enabled.
        let path3: AbsolutePath = try await withTemporaryDirectory(removeTreeOnDeinit: true) { tempDirPath in
            #expect(localFileSystem.isDirectory(tempDirPath))
            let filePath = tempDirPath.appending("somefile")
            // Do some async task
            try await Task.sleep(nanoseconds: 1_000)

            try localFileSystem.writeFileContents(filePath, bytes: [])
            return tempDirPath
        }.value
        #expect(!localFileSystem.isDirectory(path3))
    }

    @Test
    func canCreateUniqueTempDirectories() async throws {
        let (pathOne, pathTwo): (AbsolutePath, AbsolutePath) = try await withTemporaryDirectory(removeTreeOnDeinit: true) { pathOne in
            let pathTwo: AbsolutePath = try await withTemporaryDirectory(removeTreeOnDeinit: true) { pathTwo in
                // Do some async task
                try await Task.sleep(nanoseconds: 1_000)

                #expect(localFileSystem.isDirectory(pathOne))
                #expect(localFileSystem.isDirectory(pathTwo))
                // Their paths should be different.
                #expect(pathOne != pathTwo)
                return pathTwo
            }.value
            return (pathOne, pathTwo)
        }.value
        #expect(!localFileSystem.isDirectory(pathOne))
        #expect(!localFileSystem.isDirectory(pathTwo))
    }

    @Test
    func cancelOfTask() async throws {
        let task: Task<AbsolutePath, Error> = try withTemporaryDirectory { path in

            try await Task.sleep(nanoseconds: 1_000_000_000)
            #expect(Task.isCancelled)
            #expect(!localFileSystem.isDirectory(path))
            return path
        }
        task.cancel()
        await #expect(throws: (any Error).self, "Error did not error when accessing `task.value`") {
            try await task.value
        }
    }
}
