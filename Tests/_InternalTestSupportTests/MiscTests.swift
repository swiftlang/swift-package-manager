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
#if canImport(System)
import System
#else
import SystemPackage
#endif
import struct TSCBasic.ByteString

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
        .TestSize.small,
    ),
)
struct WriteNewFileCloseOnExecTests {
    @Test
    func writtenFileHasExpectedContents() throws {
        try testWithTemporaryDirectory { tmpDir in
            let path = tmpDir.appending(component: "file")
            let contents = (0..<(1 << 20)).map { UInt8(truncatingIfNeeded: $0) }

            try writeNewFileCloseOnExec(ByteString(contents), to: path)

            let actual = try localFileSystem.readFileContents(path).contents
            #expect(actual == contents)
        }
    }

    @Test
    func existingFileIsNotOverwritten() throws {
        try testWithTemporaryDirectory { tmpDir in
            let path = tmpDir.appending(component: "file")
            try localFileSystem.writeFileContents(path, string: "original")

            #expect(throws: (any Error).self) {
                try writeNewFileCloseOnExec(ByteString(encodingAsUTF8: "replacement"), to: path)
            }

            let actual: String = try localFileSystem.readFileContents(path)
            #expect(actual == "original")
        }
    }

    @Test
    func failureWhileOpenRemovesTheFile() throws {
        struct Failure: Error {}
        try testWithTemporaryDirectory { tmpDir in
            let path = tmpDir.appending(component: "file")

            #expect(throws: Failure.self) {
                try writeNewFileCloseOnExec(ByteString(encodingAsUTF8: "content"), to: path) { _ in
                    throw Failure()
                }
            }

            #expect(!localFileSystem.exists(path))
        }
    }

    @Test(
        .skipHostOS(.windows, because: "There is no concept of executable file permission")
    )
    func executableFlagControlsExecutePermission() throws {
        try testWithTemporaryDirectory { tmpDir in
            let plain = tmpDir.appending(component: "plain")
            let executable = tmpDir.appending(component: "executable")

            try writeNewFileCloseOnExec(ByteString(encodingAsUTF8: "content"), to: plain)
            try writeNewFileCloseOnExec(ByteString(encodingAsUTF8: "content"), to: executable, executable: true)

            #expect(!localFileSystem.isExecutableFile(plain))
            #expect(localFileSystem.isExecutableFile(executable))
        }
    }

    #if !os(Windows)
    @Test
    func descriptorIsMarkedCloseOnExec() throws {
        try testWithTemporaryDirectory { tmpDir in
            let path = tmpDir.appending(component: "file")
            var flags: Int32 = -1

            try writeNewFileCloseOnExec(ByteString(encodingAsUTF8: "content"), to: path) { file in
                flags = fcntl(file.rawValue, F_GETFD)
            }

            #expect(flags != -1)
            #expect(flags & FD_CLOEXEC != 0)
        }
    }

    @Test
    func descriptorIsNotInheritedByProcessSpawnedWhileFileIsOpen() throws {
        try testWithTemporaryDirectory { tmpDir in
            let path = tmpDir.appending(component: "file")
            var childExitStatus: Int32?

            try writeNewFileCloseOnExec(ByteString(encodingAsUTF8: "content"), to: path) { file in
                childExitStatus = try spawnAndWait("/bin/sh", "-c", "test -e /dev/fd/\(file.rawValue)")
            }

            // `test -e` fails when the descriptor is not open in the child.
            #expect(childExitStatus == 1)
        }
    }
    #endif
}

#if !os(Windows)
/// Spawns `executable` with plain `posix_spawn`, which inherits every descriptor that is not close-on-exec, and returns its exit status.
private func spawnAndWait(_ executable: String, _ arguments: String...) throws -> Int32 {
    let argv = ([executable] + arguments).map { strdup($0) } + [nil]
    defer { argv.forEach { free($0) } }

    var pid: pid_t = 0
    let spawnResult = posix_spawn(&pid, executable, nil, nil, argv, environ)
    guard spawnResult == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(spawnResult))
    }

    var status: Int32 = 0
    while waitpid(pid, &status, 0) == -1 {
        guard errno == EINTR else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }
    return (status >> 8) & 0xff
}
#endif

@Suite(
    .tags(
        .TestSize.small,
    ),
)
struct WriteExecutableFileTests {
    @Test
    func writtenFileHasExpectedContents() throws {
        try testWithTemporaryDirectory { tmpDir in
            let path = tmpDir.appending(component: "script")

            try writeExecutableFile("echo hello", to: path)

            let actual: String = try localFileSystem.readFileContents(path)
            #expect(actual == "echo hello")
        }
    }

    @Test(
        .skipHostOS(.windows, because: "There is no concept of executable file permission")
    )
    func writtenFileIsExecutable() throws {
        try testWithTemporaryDirectory { tmpDir in
            let path = tmpDir.appending(component: "script")

            try writeExecutableFile("#!/bin/sh\nexit 0\n", to: path)

            #expect(localFileSystem.isExecutableFile(path))
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
