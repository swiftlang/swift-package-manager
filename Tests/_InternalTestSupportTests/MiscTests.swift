//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Foundation

import SPMBuildCore
import _InternalTestSupport
import Testing
import Basics

@Suite(
    .tags(
        .TestSize.small,
    ),
)
struct TestGetNumberOfMatches {
    @Test(
        arguments: [
            (
                matchOn: "",
                value: "",
                expectedNumMatches: 0,
                id: "Empty string matches on empty string zero times",
            ),
            (
                matchOn: "",
                value: "This is a non-empty string",
                expectedNumMatches: 0,
                id: "Empty string matches on non-empty string zero times",
            ),
            (
                matchOn: "",
                value: "This is a non-empty string\nThis is the second line",
                expectedNumMatches: 0,
                id: "Empty string matches on non-empty multiline string with new line character zero times",
            ),
            (
                matchOn: "",
                value: """
                    This is a non-empty string
                    This is the second line
                    This is the third line
                    """,
                expectedNumMatches: 0,
                id: "Empty string matches on non-empty multiline string using triple double quotes zero times",
            ),
            (
                matchOn: """
                    This is a non-empty string
                    This is the second line
                    This is the third line
                    """,
                value: "",
                expectedNumMatches: 0,
                id: "non-empty string matches on empty string zero times",
            ),
            (
                matchOn: "error: fatalError",
                value: """
                    > swift test                                                                                          25/10/24 10:44:14
                    Building for debugging...
                    /Users/arandomuser/Documents/personal/repro-swiftpm-6605/Tests/repro-swiftpm-6605Tests/repro_swiftpm_6605Tests.swift:7:19: error: division by zero
                            let y = 1 / x
                                    ^
                    error: fatalError

                    error: fatalError
                    """,
                expectedNumMatches: 2,
                id: "fatal error matches on multiline with two occurrences returns two",
            ),
            (
                matchOn: "\nerror: fatalError",
                value: """
                    > swift test                                                                                          25/10/24 10:44:14
                    Building for debugging...
                    /Users/arandomuser/Documents/personal/repro-swiftpm-6605/Tests/repro-swiftpm-6605Tests/repro_swiftpm_6605Tests.swift:7:19: error: division by zero
                            let y = 1 / x
                                    ^
                    error: fatalError

                    error: fatalError
                    """,
                expectedNumMatches: 2,
                id: "fatal error with leading new line matches on multi line with two occurences returns two",
            ),
            (
                matchOn: "\nerror: fatalError\n",
                value: """
                    > swift test                                                                                          25/10/24 10:44:14
                    Building for debugging...
                    /Users/arandomuser/Documents/personal/repro-swiftpm-6605/Tests/repro-swiftpm-6605Tests/repro_swiftpm_6605Tests.swift:7:19: error: division by zero
                            let y = 1 / x
                                    ^
                    error: fatalError

                    error: fatalError
                    """,
                expectedNumMatches: 1,
                id: "fatal error with leading and trailing new line matches on multi line with two occurences returns two",
            ),
        ]
    )
    func getNumberOfMatchesReturnsExpectedValue(
        matchOn: String,
        value: String,
        expectedNumMatches: Int,
        id: String,
    ) async throws {
        let actual = getNumberOfMatches(of: matchOn, in: value)

        #expect(actual == expectedNumMatches)
    }
}

@Suite(
    .tags(
        .TestSize.small,
    ),
)
struct TestGetBuildSystemArgs {
    @Test
    func nilArgumentReturnsEmptyArray() {
        let expected: [String] = []
        let inputUnderTest: BuildSystemProvider.Kind?  = nil

        let actual = getBuildSystemArgs(for: inputUnderTest)

        #expect(actual == expected)
    }

    @Test(
        arguments: SupportedBuildSystemOnAllPlatforms
    )
    func validArgumentsReturnsCorrectCommandLineArguments(_ inputValue: BuildSystemProvider.Kind) {
        let expected = [
            "--build-system",
            "\(inputValue)"
        ]

        let actual = getBuildSystemArgs(for: inputValue)

        #expect(actual == expected)
    }
}

@Suite(
    .tags(
        .TestSize.small,
    ),
)
struct CopyFileAtomicallyTests {
    @Test
    func copyingRegularFileProducesIdenticalContentAtDestination() throws {
        try testWithTemporaryDirectory { tmpDir in
            let source = tmpDir.appending(component: "source.txt")
            let expectedContents = "hello atomic copy"
            try localFileSystem.writeFileContents(source, string: expectedContents)
            let destination = tmpDir.appending(component: "destination.txt")

            try copyFileAtomically(from: source, to: destination)

            let actualContents: String = try localFileSystem.readFileContents(destination)
            #expect(actualContents == expectedContents)
        }
    }

    @Test(
        .skipHostOS(.windows, because: "There is no concept of executable file permission")
    )
    func copyingExecutableFilePreservesExecutableBitAtDestination() throws {
        try testWithTemporaryDirectory { tmpDir in
            let source = tmpDir.appending(component: "source")
            try localFileSystem.writeFileContents(source, string: "#!/bin/sh\nexit 0\n")
            try localFileSystem.chmod(.executable, path: source, options: [])
            let destination = tmpDir.appending(component: "destination")

            try copyFileAtomically(from: source, to: destination)

            #expect(localFileSystem.isExecutableFile(destination) == true)
        }
    }

    @Test
    func copyingNonExecutableFileDoesNotMarkDestinationExecutable() throws {
        try testWithTemporaryDirectory { tmpDir in
            let source = tmpDir.appending(component: "source.txt")
            try localFileSystem.writeFileContents(source, string: "not executable")
            let destination = tmpDir.appending(component: "destination.txt")

            try copyFileAtomically(from: source, to: destination)

            #expect(localFileSystem.isExecutableFile(destination) == false)
        }
    }

    @Test
    func copyingFileLeavesNoTemporaryArtifactsInDestinationDirectory() throws {
        try testWithTemporaryDirectory { tmpDir in
            let source = tmpDir.appending(component: "source.txt")
            try localFileSystem.writeFileContents(source, string: "content")
            let destination = tmpDir.appending(component: "destination.txt")

            try copyFileAtomically(from: source, to: destination)

            let entries = try localFileSystem.getDirectoryContents(tmpDir)
            #expect(Set(entries) == Set(["source.txt", "destination.txt"]))
        }
    }

    @Test
    func copyingToAnExistingDestinationThrows() throws {
        try testWithTemporaryDirectory { tmpDir in
            let source = tmpDir.appending(component: "source.txt")
            try localFileSystem.writeFileContents(source, string: "content")
            let destination = tmpDir.appending(component: "destination.txt")
            try localFileSystem.writeFileContents(destination, string: "already here")

            #expect(throws: (any Error).self) {
                try copyFileAtomically(from: source, to: destination)
            }
        }
    }
}

@Suite(
    .tags(
        .TestSize.medium,
    ),
)
struct CopyThenExecuteExecutableFileTests {
    @Test
    func copiedExecutableRunsImmediatelyAfterCopyRepeatedly() async throws {
        try await testWithTemporaryDirectory { tmpDir in
            #if os(Windows)
            let scriptContents = "@echo off\r\nexit /b 0\r\n"
            #else
            let scriptContents = "#!/bin/sh\nexit 0\n"
            #endif

            let source = tmpDir.appending(component: "source-script\(ProcessInfo.batSuffix)")
            try localFileSystem.writeFileContents(source, string: scriptContents)
            #if !os(Windows)
            try localFileSystem.chmod(.executable, path: source, options: [])
            #endif

            for i in 0..<100 {
                let destination = tmpDir.appending(component: "copy-\(i)\(ProcessInfo.batSuffix)")
                try copyFileAtomically(from: source, to: destination)

                do {
                    try await AsyncProcess.checkNonZeroExit(arguments: [destination.pathString])
                } catch {
                    Issue.record("iteration \(i) did not exit with return code 0: \(error)")
                }
            }
        }
    }
}
