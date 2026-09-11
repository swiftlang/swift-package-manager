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
            let fakeSwiftc = try Self.makeFakeSwiftc(
                in: tmpdir,
                unixScript: """
                #!/bin/sh
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
                swiftCompilerPath: fakeSwiftc
            )

            let fileToScan = tmpdir.appending("File.swift")
            try localFileSystem.writeFileContents(fileToScan, string: "")

            let error = await #expect(throws: StringError.self) {
                try await scanner.scanImports(fileToScan)
            }
            let description = try #require(error).description
            #expect(description.contains(fakeSwiftc.pathString))
            #expect(description.contains("fake swiftc stdout"))
            #expect(description.contains("fake swiftc stderr"))
        }
    }

    @Test
    func scanImportsThrowsDescriptiveErrorOnInvalidOutput() async throws {
        try await testWithTemporaryDirectory { tmpdir in
            let fakeSwiftc = try Self.makeFakeSwiftc(
                in: tmpdir,
                unixScript: """
                #!/bin/sh
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
                swiftCompilerPath: fakeSwiftc
            )

            let fileToScan = tmpdir.appending("File.swift")
            try localFileSystem.writeFileContents(fileToScan, string: "")

            let error = await #expect(throws: StringError.self) {
                try await scanner.scanImports(fileToScan)
            }
            let description = try #require(error).description
            #expect(description.contains(fakeSwiftc.pathString))
            #expect(description.contains("this is not valid JSON"))
        }
    }

    /// Writes a fake `swiftc` executable to `tmpdir` that ignores its arguments and behaves according to the
    /// given script, then returns its path.
    private static func makeFakeSwiftc(
        in tmpdir: AbsolutePath,
        unixScript: String,
        windowsScript: String
    ) throws -> AbsolutePath {
        #if os(Windows)
        let fakeSwiftc = tmpdir.appending("swiftc.cmd")
        try localFileSystem.writeFileContents(fakeSwiftc, string: windowsScript)
        #else
        let fakeSwiftc = tmpdir.appending("swiftc")
        try localFileSystem.writeFileContents(fakeSwiftc, string: unixScript)
        try localFileSystem.chmod(.executable, path: fakeSwiftc, options: [])
        #endif
        return fakeSwiftc
    }
}
