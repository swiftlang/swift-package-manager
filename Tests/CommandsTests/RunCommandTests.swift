//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import class Foundation.ProcessInfo
import Foundation

import Basics
import Commands
import struct SPMBuildCore.BuildSystemProvider
import _InternalTestSupport
import TSCTestSupport
import Testing

import enum PackageModel.BuildConfiguration
import class Basics.AsyncProcess

@Suite(
    .serialized, // to limit the number of swift executable running.
    .tags(
        Tag.TestSize.large,
        Tag.Feature.Command.Run,
    ),
)
struct RunCommandTests {

    private func execute(
        _ args: [String] = [],
        _ executable: String? = nil,
        packagePath: AbsolutePath? = nil,
        buildSystem: BuildSystemProvider.Kind
    ) async throws -> (stdout: String, stderr: String) {
        return try await executeSwiftRun(
            packagePath,
            nil,
            extraArgs: args,
            buildSystem: buildSystem,
        )
    }

    @Test(
        arguments: SupportedBuildSystemOnPlatform,
    )
    func usage(
        buildSystem: BuildSystemProvider.Kind
    ) async throws {
        let stdout = try await execute(["-help"], buildSystem: buildSystem).stdout

        #expect(stdout.contains("USAGE: swift run <options>") || stdout.contains("USAGE: swift run [<options>]"), "got stdout:\n \(stdout)")
    }

    @Test(
        arguments: SupportedBuildSystemOnPlatform,
    )
    func seeAlso(
        buildSystem: BuildSystemProvider.Kind
    ) async throws {
        let stdout = try await execute(["--help"], buildSystem: buildSystem).stdout
        #expect(stdout.contains("SEE ALSO: swift build, swift package, swift test"), "got stdout:\n \(stdout)")
    }

    @Test(
        arguments: SupportedBuildSystemOnPlatform,
    )
    func commandDoesNotEmitDuplicateSymbols(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let duplicateSymbolRegex = try #require(duplicateSymbolRegex)
        let (stdout, stderr) = try await execute(["--help"], buildSystem: buildSystem)
        #expect(!stdout.contains(duplicateSymbolRegex))
        #expect(!stderr.contains(duplicateSymbolRegex))
    }

    @Test(
        arguments: SupportedBuildSystemOnPlatform,
    )
    func version(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let stdout = try await execute(["--version"], buildSystem: buildSystem).stdout
        let versionRegex = try Regex(#"Swift Package Manager -( \w+ )?\d+.\d+.\d+(-\w+)?"#)
        #expect(stdout.contains(versionRegex))
    }

    @Test(
        .IssueWindowsPathTestsFailures,
        .IssueWindowsRelativePathAssert,
        .SWBINTTODO("Test package fails to build on Windows"),
        .tags(
            .Feature.CommandLineArguments.Toolset,
        ),
        .tags(
            .Feature.CommandLineArguments.BuildSystem,
            .Feature.CommandLineArguments.Configuration,
        ),
        arguments: SupportedBuildSystemOnPlatform,
    )
    func toolsetDebugger(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Miscellaneous/EchoExecutable") { fixturePath in
            #if os(Windows)
                let win32 = ".win32"
            #else
                let win32 = ""
            #endif
            let (stdout, stderr) = try await execute(
                    ["--toolset", "\(fixturePath.appending("toolset\(win32).json").pathString)"],
                    packagePath: fixturePath,
                    buildSystem: buildSystem,
                )

            // We only expect tool's output on the stdout stream.
            #expect(stdout.contains("\(fixturePath.appending(".build").pathString)"))
            #expect(stdout.contains("sentinel"))

            // swift-build-tool output should go to stderr.
            switch buildSystem {
                case .native:
                    #expect(stderr.contains("Compiling"))
                    #expect(stderr.contains("Linking"))
                case .swiftbuild, .xcode:
                    break
            }
        }
    }

    @Test(
         .tags(
            .Feature.TargetType.Executable,
        ),
        arguments: SupportedBuildSystemOnPlatform,
    )
    func productArgumentPassing(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Miscellaneous/EchoExecutable") { fixturePath in
            let (stdout, stderr) = try await execute(
                ["secho", "1", "--hello", "world"],
                packagePath: fixturePath,
                buildSystem: buildSystem,
            )

            // We only expect tool's output on the stdout stream.
            #expect(stdout.contains("""
                "1" "--hello" "world"
                """))

            // swift-build-tool output should go to stderr.
            switch buildSystem {
                case .native:
                    #expect(stderr.contains("Compiling"))
                    #expect(stderr.contains("Linking"))
                case .swiftbuild, .xcode:
                    break
            }
        }
    }

    @Test(
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8279"),
        arguments: SupportedBuildSystemOnPlatform,
    )
    func unknownProductRaisesAnError(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Miscellaneous/EchoExecutable") { fixturePath in
            let error = await #expect(throws: SwiftPMError.self ) {
                try await execute(["unknown"], packagePath: fixturePath, buildSystem: buildSystem)
            }
            guard case SwiftPMError.executionFailure(_, let stdout, let stderr) = try #require(error) else {
                Issue.record("Incorrect error was raised.")
                return
            }

            #expect(
                stderr.contains("error: no executable product named 'unknown'"),
                "got stdout: \(stdout), stderr: \(stderr)",
            )

        }
    }


    @Test(
         .tags(
            .Feature.TargetType.Executable,
        ),
        .SWBINTTODO("Swift run using Swift Build does not output executable content to the terminal"),
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8279"),
        arguments: SupportedBuildSystemOnPlatform,
    )
    func multipleExecutableAndExplicitExecutable(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "Miscellaneous/MultipleExecutables") { fixturePath in

                let error = await #expect(throws: SwiftPMError.self ) {
                    try await execute(packagePath: fixturePath, buildSystem: buildSystem)
                }
                guard case SwiftPMError.executionFailure(_, let stdout, let stderr) = try #require(error) else {
                    Issue.record("Incorrect error was raised.")
                    return
                }

                #expect(
                    stderr.contains("error: multiple executable products available: exec1, exec2"),
                    "got stdout: \(stdout), stderr: \(stderr)",
                )

                var (runOutput, _) = try await execute(["exec1"], packagePath: fixturePath, buildSystem: buildSystem)
                #expect(runOutput.contains("1"))

                (runOutput, _) = try await execute(["exec2"], packagePath: fixturePath, buildSystem: buildSystem)
                #expect(runOutput.contains("2"))
            }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild
        }
    }


    @Test(
        .tags(
            .Feature.TargetType.Executable,
        ),
        .IssueWindowsPathTestsFailures,
        .IssueWindowsRelativePathAssert,
        arguments: SupportedBuildSystemOnPlatform,
    )
    func unreachableExecutable(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "Miscellaneous/UnreachableTargets") { fixturePath in
                let (output, _) = try await execute(["bexec"], packagePath: fixturePath.appending("A"), buildSystem: buildSystem)
                let outputLines = output.split(whereSeparator: { $0.isNewline })
                #expect(String(outputLines[0]).contains("BTarget2"))
            }
        } when: {
            (ProcessInfo.hostOperatingSystem == .windows && CiEnvironment.runningInSmokeTestPipeline && [.native, .swiftbuild].contains(buildSystem))
        }
    }

    @Test(
        .tags(
            .Feature.TargetType.Executable,
        ),
        arguments: SupportedBuildSystemOnPlatform,
    )
    func fileDeprecation(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "Miscellaneous/EchoExecutable") { fixturePath in
                let filePath = AbsolutePath(fixturePath, "Sources/secho/main.swift").pathString
                let cwd = try #require(localFileSystem.currentWorkingDirectory, "Current working directory should not be nil")
                let (stdout, stderr) = try await execute([filePath, "1", "2"], packagePath: fixturePath, buildSystem: buildSystem)
                #expect(stdout.contains(#""\#(cwd)" "1" "2""#))
                #expect(stderr.contains("warning: 'swift run \(filePath)' command to interpret swift files is deprecated; use 'swift \(filePath)' instead"))
            }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows
        }
    }

    @Test(
        .tags(
            .Feature.TargetType.Executable,
            .Feature.CommandLineArguments.BuildTests,
            .Feature.CommandLineArguments.SkipBuild
        ),
        arguments: SupportedBuildSystemOnPlatform,
    )
    func mutualExclusiveFlags(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Miscellaneous/EchoExecutable") { fixturePath in
            let error = await #expect(throws: SwiftPMError.self ) {
                try await execute(["--build-tests", "--skip-build"], packagePath: fixturePath, buildSystem: buildSystem)
            }
            guard case SwiftPMError.executionFailure(_, let stdout, let stderr) = try #require(error) else {
                Issue.record("Incorrect error was raised.")
                return
            }

            #expect(
                stderr.contains("error: '--build-tests' and '--skip-build' are mutually exclusive"),
                "got stdout: \(stdout), stderr: \(stderr)",
            )
        }
    }

    @Test(
        .tags(
            .Feature.TargetType.Executable,
        ),
        arguments: SupportedBuildSystemOnPlatform,
    )
    func swiftRunSIGINT(
        buildSystem: BuildSystemProvider.Kind,
    ) throws {
        try withKnownIssue("Seems to be flaky in CI", isIntermittent: true) {
            try fixture(name: "Miscellaneous/SwiftRun") { fixturePath in
                let mainFilePath = fixturePath.appending("main.swift")
                try localFileSystem.removeFileTree(mainFilePath)
                try localFileSystem.writeFileContents(
                    mainFilePath,
                    string: """
                    import Foundation

                    print("sleeping")
                    fflush(stdout)

                    Thread.sleep(forTimeInterval: 10)
                    print("done")
                    """
                )

                let sync = DispatchGroup()
                let outputHandler = OutputHandler(sync: sync)

                var environment = Environment.current
                environment["SWIFTPM_EXEC_NAME"] = "swift-run"
                let process = AsyncProcess(
                    arguments: [SwiftPM.Run.xctestBinaryPath.pathString, "--package-path", fixturePath.pathString],
                    environment: environment,
                    outputRedirection: .stream(stdout: outputHandler.handle(bytes:), stderr: outputHandler.handle(bytes:))
                )

                sync.enter()
                try process.launch()

                // wait for the process to start
                try #require(sync.wait(timeout: .now() + .seconds(300)) != .timedOut, "timeout waiting for process to start")

                // interrupt the process
                print("interrupting")
                process.signal(SIGINT)

                // check for interrupt result
                let result = try process.waitUntilExit()
    #if os(Windows)
                #expect(result.exitStatus == .abnormal(exception: 2))
    #else
                #expect(result.exitStatus == .signalled(signal: SIGINT))
    #endif
            }

            class OutputHandler {
                let sync: DispatchGroup
                var state = State.idle
                let lock = NSLock()

                init(sync: DispatchGroup) {
                    self.sync = sync
                }

                @Sendable func handle(bytes: [UInt8]) {
                    guard let output = String(bytes: bytes, encoding: .utf8) else {
                        return
                    }
                    print(output, terminator: "")
                    self.lock.withLock {
                        switch self.state {
                        case .idle:
                            self.state = processOutput(output)
                        case .buffering(let buffer):
                            let newBuffer = buffer + output
                            self.state = processOutput(newBuffer)
                        case .done:
                            break //noop
                        }
                    }

                    func processOutput(_ output: String) -> State {
                        if output.contains("sleeping") {
                            self.sync.leave()
                            return .done
                        } else {
                            return .buffering(output)
                        }
                    }
                }

                enum State {
                    case idle
                    case buffering(String)
                    case done
                }
            }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows && (CiEnvironment.runningInSmokeTestPipeline || CiEnvironment.runningInSelfHostedPipeline)
        }
    }

    @Test(
        .tags(
            .Feature.TargetType.Executable,
            .Feature.CommandLineArguments.Quiet
        ),
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8844", relationship: .verifies),
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8911", relationship: .defect),
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8912", relationship: .defect),
        arguments: SupportedBuildSystemOnPlatform, BuildConfiguration.allCases,
    )
    func swiftRunQuietLogLevel(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
    ) async throws {
        try await withKnownIssue(isIntermittent: true) {
            // GIVEN we have a simple test package
            try await fixture(name: "Miscellaneous/SwiftRun") { fixturePath in
               //WHEN we run with the --quiet option
               let (stdout, stderr) = try await executeSwiftRun(
                   fixturePath,
                   nil,
                   configuration: configuration,
                   extraArgs: ["--quiet"],
                   buildSystem: buildSystem
               )
               // THEN we should not see any output in stderr
                #expect(stderr.isEmpty)
               // AND no content in stdout
                #expect(stdout == "done\n")
           }
        } when: {
           (CiEnvironment.runningInSmokeTestPipeline && ProcessInfo.hostOperatingSystem == .windows)
        }
    }

    @Test(
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8844"),
        arguments: SupportedBuildSystemOnPlatform,
    )
    func swiftRunQuietLogLevelWithError(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        // GIVEN we have a simple test package
        try await fixture(name: "Miscellaneous/SwiftRun") { fixturePath in
            let mainFilePath = fixturePath.appending("main.swift")
            try localFileSystem.removeFileTree(mainFilePath)
            try localFileSystem.writeFileContents(
                mainFilePath,
                string: """
                print("done"
                """
            )

            //WHEN we run with the --quiet option
            let error = await #expect(throws: SwiftPMError.self) {
                try await executeSwiftRun(
                    fixturePath,
                    nil,
                    configuration: configuration,
                    extraArgs: ["--quiet"],
                    buildSystem: buildSystem
                )
            }

            guard case SwiftPMError.executionFailure(_, let stdout, let stderr) = try #require(error) else {
                Issue.record("Incorrect error was raised.")
                return
            }

            // THEN we should see an output in stderr
            #expect(stderr.isEmpty == false)
            // AND no content in stdout
            #expect(stdout.isEmpty)
        }
    }
}
