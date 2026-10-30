//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import Testing
import _InternalTestSupport

@testable import Basics

#if !os(Windows)

@Suite(.requires(executable: "zip"), .requires(executable: "unzip"))
struct ZipArchiverCompressTests {
    @Test
    func compressAndExtractWithSpacesInPaths() async throws {
        try await withTemporaryDirectory(removeTreeOnDeinit: true) { tmpdir in
            let archiver = ZipArchiver(fileSystem: localFileSystem)

            let rootDir = tmpdir.appending(component: "dir with spaces")
            try localFileSystem.createDirectory(rootDir)
            try localFileSystem.writeFileContents(rootDir.appending("a file.txt"), string: "Hello World!")

            let archivePath = tmpdir.appending(component: "my archive.zip")
            try await archiver.compress(directory: rootDir, to: archivePath)
            #expect(localFileSystem.exists(archivePath))

            let extractRootDir = tmpdir.appending(component: "extracted dir")
            try localFileSystem.createDirectory(extractRootDir)
            try await archiver.extract(from: archivePath, to: extractRootDir)
            #expect(localFileSystem.exists(extractRootDir.appending(components: "dir with spaces", "a file.txt")))
        }
    }

    @Test
    func extractErrorReportsStandardErrorOnly() async throws {
        try await withTemporaryDirectory(removeTreeOnDeinit: true) { tmpdir in
            let archiver = ZipArchiver(fileSystem: localFileSystem)
            // Not a zip archive: `unzip` prints "Archive: <path>" to stdout and the actual problem to stderr.
            let notAnArchive = tmpdir.appending("not-an-archive.zip")
            try localFileSystem.writeFileContents(notAnArchive, string: "this is not a zip file")

            let error = await #expect(throws: StringError.self) {
                try await archiver.extract(from: notAnArchive, to: tmpdir)
            }
            let message = error?.description ?? ""
            #expect(!message.isEmpty)
            #expect(!message.contains("Archive:"), "unzip's progress output on stdout leaked into the error: \(message)")
        }
    }
}

#endif
