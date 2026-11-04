//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
import Subprocess
#if canImport(System)
import System
#else
import SystemPackage
#endif

import enum TSCBasic.ProcessEnv

package struct NonZeroExitError: Error, CustomStringConvertible {
    package let terminationStatus: TerminationStatus
    /// The command that exited with a non-zero status: the SwiftPM executable and its arguments.
    package let command: [String]

    package var description: String {
        "'\(self.command.joined(separator: " "))' exited with \(self.terminationStatus)"
    }
}

// Fan out from invocation of SPM 'swift-*' commands can be quite large.  Limit the number of concurrent tasks to a fraction of total CPUs.
private let swiftPMExecutionQueue = AsyncOperationQueue(concurrentTasks: Int(Double(ProcessInfo.processInfo.activeProcessorCount) * 0.5))

/// Defines the executables used by SwiftPM.
/// Contains path to the currently built executable and
/// helper method to execute them.
public enum SwiftPM {
    case Build
    case Package
    case Registry
    case Test
    case Run
    case experimentalSDK
    case sdk
}

extension SwiftPM {
    /// Executable name.
    private var executableName: String {
        switch self {
        case .Build:
            return "swift-build"
        case .Package:
            return "swift-package"
        case .Registry:
            return "swift-package-registry"
        case .Test:
            return "swift-test"
        case .Run:
            return "swift-run"
        case .experimentalSDK:
            return "swift-experimental-sdk"
        case .sdk:
            return "swift-sdk"
        }
    }

    public var xctestBinaryPath: AbsolutePath {
        Self.xctestBinaryPath(for: RelativePath(self.executableName))
    }

    public static func xctestBinaryPath(for executableName: RelativePath) -> AbsolutePath {
        do {
            return try resolveBinDir().appending(executableName)
        } catch {
            fatalError("Unable to determine xctestBinaryPath")
        }
    }
}

extension SwiftPM {
    /// Executes the product with specified arguments.
    ///
    /// - Parameters:
    ///         - args: The arguments to pass.
    ///         - env: Additional environment variables to pass. The values here are merged with default env.
    ///         - packagePath: Adds argument `--package-path <path>` if not nil.
    ///         - throwIfCommandFails: If set, will throw an error if the command does not have a 0 return code.
    ///
    /// - Returns: The output of the process.
    @discardableResult
    public func execute(
        _ args: [String] = [],
        packagePath: AbsolutePath? = nil,
        env: Basics.Environment? = nil,
        throwIfCommandFails: Bool = true,
        commandPrefix: [String] = [],
    ) async throws -> (stdout: String, stderr: String) {
        // Swift Testing uses Swift concurrency for test execution and creates a task for each test to run in parallel.
        // A single invocation of "swift build" can spawn a large number of subprocesses.
        // When this pattern is repeated across many tests, thousands of processes compete for
        // CPU/disk/network resources. Tests can take thousands of seconds to complete, with periods
        // of no stdout/stderr output that can cause activity timeouts in CI pipelines.
        // Run all SPM executions under a queue to limit the maximum number of concurrent SPM processes.
        try await swiftPMExecutionQueue.withOperation {
            let result = try await executeProcess(
                args,
                packagePath: packagePath,
                env: env,
                commandPrefix: commandPrefix,
            )
            // Remove /r from stdout/stderr so that tests do not have to deal with them
            let stdout = String(decoding: result.stdout.filter { $0 != 13 }, as: Unicode.UTF8.self)
            let stderr = String(decoding: result.stderr.filter { $0 != 13 }, as: Unicode.UTF8.self)

            let returnValue = (stdout: stdout, stderr: stderr)
            if !throwIfCommandFails { return returnValue }

            if result.terminationStatus.isSuccess {
                return returnValue
            }
            throw SwiftPMError.executionFailure(
                underlying: NonZeroExitError(
                    terminationStatus: result.terminationStatus,
                    command: [self.executableName] + args
                ),
                stdout: stdout,
                stderr: stderr
            )
        }
    }

    /// The environment SwiftPM tool invocations run in.
    private func makeEnvironment(overriding env: Basics.Environment?) -> Basics.Environment {
        var environment = Basics.Environment.current
#if !os(Windows)
        environment["SDKROOT"] = nil
#endif

#if Xcode
        // Unset these variables which causes issues when running tests via Xcode.
        environment["XCTestConfigurationFilePath"] = nil
        environment["XCTestSessionIdentifier"] = nil
        environment["XCTestBundlePath"] = nil
        environment["NSUnbufferedIO"] = nil
#endif
        // FIXME: We use this private environment variable hack to be able to
        // create special conditions in swift-build for swiftpm tests.
        environment["SWIFTPM_TESTS_MODULECACHE"] = self.xctestBinaryPath.parentDirectory.pathString

        // Unset the internal env variable that allows skipping certain tests.
        environment["_SWIFTPM_SKIP_TESTS_LIST"] = nil

        for (key, value) in env ?? [:] {
            environment[key] = value
        }
        return environment
    }

    private func makeCommandLine(_ args: [String], packagePath: AbsolutePath?, commandPrefix: [String]) -> [String] {
        var completeArgs = commandPrefix + [Self.xctestBinaryPath(for: RelativePath(self.executableName)).pathString]
        if let packagePath = packagePath {
            completeArgs += ["--package-path", packagePath.pathString]
        }
        completeArgs += args
        return completeArgs
    }

    /// Starts the command and returns without waiting for it to finish, for tests that need to signal it while it runs.
    ///
    /// The command's standard output and standard error are written to the given files. Standard input is closed.
    public func launch(
        _ args: [String] = [],
        packagePath: AbsolutePath? = nil,
        env: Basics.Environment? = nil,
        standardOutputFile: AbsolutePath,
        standardErrorFile: AbsolutePath
    ) throws -> Foundation.Process {
        let completeArgs = makeCommandLine(args, packagePath: packagePath, commandPrefix: [])
        let process = Foundation.Process()
        process.executableURL = URL(fileURLWithPath: completeArgs[0])
        process.arguments = Array(completeArgs.dropFirst())
        process.environment = Dictionary(
            uniqueKeysWithValues: self.makeEnvironment(overriding: env).removingKeysInvalidForSubprocess.map {
                ($0.key.rawValue, $0.value)
            }
        )
        process.standardInput = FileHandle.nullDevice
        for (path, setter) in [
            (standardOutputFile, { (handle: FileHandle) in process.standardOutput = handle }),
            (standardErrorFile, { (handle: FileHandle) in process.standardError = handle }),
        ] {
            FileManager.default.createFile(atPath: path.pathString, contents: nil)
            setter(try FileHandle(forWritingTo: URL(fileURLWithPath: path.pathString)))
        }
        try process.run()
        return process
    }

    private func executeProcess(
        _ args: [String],
        packagePath: AbsolutePath? = nil,
        env: Basics.Environment? = nil,
        commandPrefix: [String],
    ) async throws -> (stdout: [UInt8], stderr: [UInt8], terminationStatus: TerminationStatus) {
        let environment = self.makeEnvironment(overriding: env)
        let completeArgs = self.makeCommandLine(args, packagePath: packagePath, commandPrefix: commandPrefix)

        let result = try await Subprocess.run(
            .path(FilePath(completeArgs[0])),
            arguments: Subprocess.Arguments(Array(completeArgs.dropFirst())),
            environment: Subprocess.Environment.custom(
                Dictionary(uniqueKeysWithValues: environment.removingKeysInvalidForSubprocess.map {
                    (Subprocess.Environment.Key(rawValue: $0.key.rawValue)!, $0.value)
                })
            ),
            output: .bytes(limit: .max),
            error: .bytes(limit: .max)
        )
        return (
            stdout: result.standardOutput,
            stderr: result.standardError,
            terminationStatus: result.terminationStatus
        )
    }
}

extension SwiftPM {
    public static func packagePath(for packageName: String, packageRoot: AbsolutePath) throws -> AbsolutePath {
        // FIXME: The directory paths are hard coded right now and should be replaced by --get-package-path
        // whenever we design that. https://bugs.swift.org/browse/SR-2753
        let packagesPath = packageRoot.appending(components: ".build", "checkouts")
        for name in try localFileSystem.getDirectoryContents(packagesPath) {
            if name.hasPrefix(packageName) {
                return try AbsolutePath(validating: name, relativeTo: packagesPath)
            }
        }
        throw SwiftPMError.packagePathNotFound
    }
}

public enum SwiftPMError: Error {
    case packagePathNotFound
    case executionFailure(underlying: Error, stdout: String, stderr: String)
}

@available(*, deprecated, message: "Use SwiftPMError instead")
public enum SwiftPMProductError: Swift.Error {
    case packagePathNotFound
    case executionFailure(error: Swift.Error, output: String, stderr: String)
}
