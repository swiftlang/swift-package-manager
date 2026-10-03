//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import _InternalTestSupport
import Testing

struct ImportScanningTests {
    @Test
    func scanImportsThrowsDescriptiveErrorOnNonZeroExit() async throws {
        try await testWithTemporaryDirectory { tmpdir in
            let (swiftCompilerPath, fileToScan) = try Self.makeFakeSwiftc(
                in: tmpdir,
                unixScript: """
                echo "fake swiftc stdout"
                echo "fake swiftc stderr" 1>&2
                exit 1
                """,
                windowsScript: """
                @echo off
                echo fake swiftc stdout
                echo fake swiftc stderr 1>&2
                exit /b 1
                """
            )

            let scanner = SwiftcImportScanner(
                swiftCompilerEnvironment: .current,
                swiftCompilerFlags: [],
                swiftCompilerPath: swiftCompilerPath
            )

            let error = await #expect(throws: StringError.self) {
                try await scanner.scanImports(fileToScan)
            }
            let description = try #require(error).description
            #expect(description.contains(swiftCompilerPath.pathString))
            #expect(description.contains("fake swiftc stdout"))
            #expect(description.contains("fake swiftc stderr"))
        }
    }

    @Test
    func scanImportsThrowsDescriptiveErrorOnInvalidOutput() async throws {
        try await testWithTemporaryDirectory { tmpdir in
            let (swiftCompilerPath, fileToScan) = try Self.makeFakeSwiftc(
                in: tmpdir,
                unixScript: """
                echo "this is not valid JSON"
                """,
                windowsScript: """
                @echo off
                echo this is not valid JSON
                """
            )

            let scanner = SwiftcImportScanner(
                swiftCompilerEnvironment: .current,
                swiftCompilerFlags: [],
                swiftCompilerPath: swiftCompilerPath
            )

            let error = await #expect(throws: StringError.self) {
                try await scanner.scanImports(fileToScan)
            }
            let description = try #require(error).description
            #expect(description.contains(swiftCompilerPath.pathString))
            #expect(description.contains("this is not valid JSON"))
        }
    }

    /// Returns a `(swiftCompilerPath, fileToScan)` pair such that invoking the former with the latter behaves
    /// according to the given script, standing in for a misbehaving `swiftc`.
    ///
    /// On Unix, `swiftCompilerPath` is the system shell and the script is written into the *file to scan*,
    /// which `SwiftcImportScanner` passes as the shell's first argument. This deliberately avoids writing an
    /// executable and then immediately executing it: on Linux, `execve` fails with `ETXTBSY` ("Text file
    /// busy") whenever any process in the system holds a write handle on the target file, and `AsyncProcess`
    /// sets no `O_CLOEXEC` on descriptors, so every subprocess it spawns inherits whatever descriptors happen
    /// to be open at that moment. A script written by one test can therefore be held open for writing by a
    /// child process spawned by a *different* test running in parallel, making it intermittently
    /// unexecutable for as long as that unrelated child lives. Handing the script to an already-existing
    /// interpreter as plain data sidesteps that race entirely.
    private static func makeFakeSwiftc(
        in tmpdir: AbsolutePath,
        unixScript: String,
        windowsScript: String
    ) throws -> (swiftCompilerPath: AbsolutePath, fileToScan: AbsolutePath) {
        let fileToScan = tmpdir.appending("File.swift")
        #if os(Windows)
        // Windows has no ETXTBSY equivalent, so writing a batch file and executing it is safe.
        let swiftCompilerPath = tmpdir.appending("swiftc.cmd")
        try localFileSystem.writeFileContents(swiftCompilerPath, string: windowsScript)
        try localFileSystem.writeFileContents(fileToScan, string: "")
        #else
        let swiftCompilerPath = try AbsolutePath(validating: "/bin/sh")
        try localFileSystem.writeFileContents(fileToScan, string: unixScript)
        #endif
        return (swiftCompilerPath, fileToScan)
    }
}
