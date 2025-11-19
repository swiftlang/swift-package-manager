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
import SPMBuildCore
import Testing
import _InternalTestSupport

@Suite
struct TaskBacktraceTests {
    @Test(
        .tags(.TestSize.large, .Feature.TaskBacktraces)
    )
    func taskBacktraces() async throws {
        try await fixture(name: "Miscellaneous/Simple") { fixturePath in
            let (stdout, _) = try await executeSwiftBuild(
                fixturePath,
                extraArgs: ["--experimental-task-backtraces", "--verbose"],
                buildSystem: .swiftbuild
            )
            #expect(stdout.contains("Build complete!"))

            // Wait to ensure file timestamps are different on filesystems with low precision
            try await Task.sleep(for: .milliseconds(250))

            try localFileSystem.writeFileContents(
                fixturePath.appending(components: "Foo.swift"),
                bytes: "public func bar() {}"
            )

            let (incrementalStdout, incrementalStderr) = try await executeSwiftBuild(
                fixturePath,
                extraArgs: ["--experimental-task-backtraces", "--verbose"],
                buildSystem: .swiftbuild
            )
            // Add a basic check that we produce backtrace output. The specifc formatting is tested by Swift Build.
            #expect(incrementalStderr.contains("Task backtrace:"))
            #expect(
                incrementalStderr.split(separator: "\n").contains(where: {
                    $0.contains("Foo.swift' changed")
                })
            )
            #expect(incrementalStdout.contains("Build complete!"))
        }
    }

    @Test(
        .tags(.TestSize.large, .Feature.TaskBacktraces)
    )
    func taskBacktracesWarnsWithoutVerboseOutput() async throws {
        try await fixture(name: "Miscellaneous/Simple") { fixturePath in
            let (_, stderr) = try await executeSwiftBuild(
                fixturePath,
                extraArgs: ["--experimental-task-backtraces"],
                buildSystem: .swiftbuild,
                throwIfCommandFails: false
            )
            #expect(stderr.contains("'--experimental-task-backtraces' requires '--verbose' or '--very-verbose'"))
        }
    }

    @Test(
        .tags(.TestSize.large, .Feature.TaskBacktraces)
    )
    func taskBacktracesWarnsWithNonSwiftBuildSystem() async throws {
        try await fixture(name: "Miscellaneous/Simple") { fixturePath in
            let (_, stderr) = try await executeSwiftBuild(
                fixturePath,
                extraArgs: ["--experimental-task-backtraces", "--verbose"],
                buildSystem: .native,
                throwIfCommandFails: false
            )
            #expect(stderr.contains("'--experimental-task-backtraces' is only supported when using '--build-system swiftbuild'"))
        }
    }
}
