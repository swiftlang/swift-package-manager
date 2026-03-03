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

import Basics
import CoreCommands
import PackageModel
import SPMBuildCore
import TSCUtility
import Workspace

import struct TSCBasic.FileSystemError
import class Basics.AsyncProcess
import struct Basics.AsyncProcessResult
import TSCLibc
import var TSCBasic.stderrStream
import var TSCBasic.stdoutStream
import func TSCBasic.withTemporaryFile
import Foundation

/// Internal helper functionality for the SwiftTestTool command and for the
/// plugin support.
///
/// Note: In the long term this should be factored into a reusable module that
/// can run and report results on tests from both CLI and libSwiftPM API.
enum TestingSupport {
    /// Locates XCTestHelper tool inside the libexec directory and bin directory.
    /// Note: It is a fatalError if we are not able to locate the tool.
    ///
    /// - Returns: Path to XCTestHelper tool.
    static func xctestHelperPath(swiftCommandState: SwiftCommandState) throws -> AbsolutePath {
        var triedPaths = [AbsolutePath]()

        func findXCTestHelper(swiftBuildPath: AbsolutePath) -> AbsolutePath? {
            // XCTestHelper tool is installed in libexec.
            let maybePath = swiftBuildPath.parentDirectory.parentDirectory.appending(
                components: "libexec", "swift", "pm", "swiftpm-xctest-helper"
            )
            if swiftCommandState.fileSystem.isFile(maybePath) {
                return maybePath
            } else {
                triedPaths.append(maybePath)
                return nil
            }
        }

        if let firstCLIArgument = CommandLine.arguments.first {
            let runningSwiftBuildPath = try AbsolutePath(validating: firstCLIArgument, relativeTo: swiftCommandState.originalWorkingDirectory)
            if let xctestHelperPath = findXCTestHelper(swiftBuildPath: runningSwiftBuildPath) {
                return xctestHelperPath
            }
        }

        // This will be true during swiftpm development or when using swift.org toolchains.
        let xcodePath = try AsyncProcess.checkNonZeroExit(args: "/usr/bin/xcode-select", "--print-path").spm_chomp()
        let installedSwiftBuildPath = try AsyncProcess.checkNonZeroExit(
            args: "/usr/bin/xcrun", "--find", "swift-build",
            environment: ["DEVELOPER_DIR": xcodePath]
        ).spm_chomp()
        if let xctestHelperPath = findXCTestHelper(swiftBuildPath: try AbsolutePath(validating: installedSwiftBuildPath)) {
            return xctestHelperPath
        }

        throw InternalError("XCTestHelper binary not found, tried \(triedPaths.map { $0.pathString }.joined(separator: ", "))")
    }

    static func getTestSuites(
        in testProducts: [BuiltTestProduct],
        swiftCommandState: SwiftCommandState,
        enableCodeCoverage: Bool,
        shouldSkipBuilding: Bool,
        experimentalTestOutput: Bool,
        sanitizers: [Sanitizer]
    ) throws -> [AbsolutePath: [TestSuite]] {
        let testSuitesByProduct = try testProducts
            .map {(
                $0.bundlePath,
                try Self.getTestSuites(
                    fromTestAt: $0.bundlePath,
                    swiftCommandState: swiftCommandState,
                    enableCodeCoverage: enableCodeCoverage,
                    shouldSkipBuilding: shouldSkipBuilding,
                    experimentalTestOutput: experimentalTestOutput,
                    sanitizers: sanitizers
                )
            )}
        return try Dictionary(throwingUniqueKeysWithValues: testSuitesByProduct)
    }

    /// Runs the corresponding tool to get tests JSON and create TestSuite array.
    /// On macOS, we use the swiftpm-xctest-helper tool bundled with swiftpm.
    /// On Linux, XCTest can dump the json using `--dump-tests-json` mode.
    ///
    /// - Parameters:
    ///     - path: Path to the XCTest bundle(macOS) or executable(Linux).
    ///
    /// - Throws: TestError, SystemError, TSCUtility.Error
    ///
    /// - Returns: Array of TestSuite
    static func getTestSuites(
        fromTestAt path: AbsolutePath,
        swiftCommandState: SwiftCommandState,
        enableCodeCoverage: Bool,
        shouldSkipBuilding: Bool,
        experimentalTestOutput: Bool,
        sanitizers: [Sanitizer]
    ) throws -> [TestSuite] {
        // Run the correct tool.
        var args = [String]()
        #if os(macOS)
        let data: String = try withTemporaryFile { tempFile in
            args = [try Self.xctestHelperPath(swiftCommandState: swiftCommandState).pathString, path.pathString, tempFile.path.pathString]
            let env = try Self.constructTestEnvironment(
                toolchain: try swiftCommandState.getTargetToolchain(),
                destinationBuildParameters: swiftCommandState.buildParametersForTest(
                    enableCodeCoverage: enableCodeCoverage,
                    shouldSkipBuilding: shouldSkipBuilding,
                    experimentalTestOutput: experimentalTestOutput
                ).productsBuildParameters,
                sanitizers: sanitizers,
                library: .xctest,
                testProductPaths: [path],
                interopMode: nil // Interop not required when listing tests
            )
            try Self.runProcessWithExistenceCheck(
                path: path,
                fileSystem: swiftCommandState.fileSystem,
                args: args,
                env: env
            )

            // Read the temporary file's content.
            return try swiftCommandState.fileSystem.readFileContents(AbsolutePath(tempFile.path))
        }
        #else
        let env = try Self.constructTestEnvironment(
            toolchain: try swiftCommandState.getTargetToolchain(),
            destinationBuildParameters: swiftCommandState.buildParametersForTest(
                enableCodeCoverage: enableCodeCoverage,
                shouldSkipBuilding: shouldSkipBuilding
            ).productsBuildParameters,
            sanitizers: sanitizers,
            library: .xctest,
            testProductPaths: [path],
            interopMode: nil // Interop not required when listing tests
        )
        args = [path.description, "--dump-tests-json"]
        let data = try Self.runProcessWithExistenceCheck(
            path: path,
            fileSystem: swiftCommandState.fileSystem,
            args: args,
            env: env
        )
        #endif
        // Parse json and return TestSuites.
        return try TestSuite.parse(jsonString: data, context: args.joined(separator: " "))
    }

    static func getSwiftTestingSuites(
        in testProducts: [BuiltTestProduct],
        swiftCommandState: SwiftCommandState,
        shouldSkipBuilding: Bool,
        sanitizers: [Sanitizer]
    ) throws -> [AbsolutePath: [String]] {
        let suitesByProduct = try testProducts
            .map {(
                $0.binaryPath,
                try Self.getSwiftTestingSuites(
                    fromTestAt: $0.binaryPath,
                    swiftCommandState: swiftCommandState,
                    shouldSkipBuilding: shouldSkipBuilding,
                    sanitizers: sanitizers
                )
            )}
        return try Dictionary(throwingUniqueKeysWithValues: suitesByProduct)
    }

    /// Runs the test binary to list Swift Testing tests and returns their identifiers.
    /// On macOS, we use the swiftpm-testing-helper tool bundled with swiftpm.
    /// On Linux, the test binary handles `--list-tests` directly.
    ///
    /// - Parameters:
    ///     - path: Path to the test binary.
    ///
    /// - Throws: TestError, SystemError, TSCUtility.Error
    ///
    /// - Returns: Array of test identifiers in the format "Module.Suite/testFunction()"
    static func getSwiftTestingSuites(
        fromTestAt path: AbsolutePath,
        swiftCommandState: SwiftCommandState,
        shouldSkipBuilding: Bool,
        sanitizers: [Sanitizer]
    ) throws -> [String] {
        let toolchain = try swiftCommandState.getTargetToolchain()
        let env = try Self.constructTestEnvironment(
            toolchain: toolchain,
            destinationBuildParameters: swiftCommandState.buildParametersForTest(
                // Unlike the XCTest helper tool, the Swift Testing runtime initialises LLVM
                // profiling on startup and writes a profraw file even when only listing tests,
                // which would inflate the profraw file count produced by the actual test run.
                // Code coverage is not necessary here as we are simply listing tests.
                enableCodeCoverage: false,
                shouldSkipBuilding: shouldSkipBuilding
            ).productsBuildParameters,
            sanitizers: sanitizers,
            library: .swiftTesting,
            testProductPaths: [path]
        )

        var args: [String]
        #if os(macOS)
        let helper = try toolchain.getSwiftTestingHelper()
        args = [helper.pathString, "--test-bundle-path", path.pathString,
                "--list-tests", "--testing-library", "swift-testing",
                path.pathString]
        #else
        args = [path.pathString, "--list-tests", "--testing-library", "swift-testing"]
        #endif

        let output: String
        do {
            output = try Self.runProcessWithExistenceCheck(
                path: path,
                fileSystem: swiftCommandState.fileSystem,
                args: args,
                env: env
            )
        } catch AsyncProcessResult.Error.nonZeroExit(let result)
            where result.exitStatus == .terminated(code: Self.exitNoTestsFound) {
            return []
        }

        return output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The exit code used by Swift Testing when no tests are found.
    ///
    /// Because Swift Package Manager does not directly link to the testing library,
    /// it duplicates the definition of this constant in its own source. Any changes
    /// to this constant in either package must be mirrored in the other.
    private static var exitNoTestsFound: CInt {
        #if os(macOS) || os(Linux) || canImport(Android) || os(FreeBSD)
        EX_UNAVAILABLE
        #elseif os(Windows)
        ERROR_NOT_FOUND
        #else
        #warning("Platform-specific implementation missing: value for exitNoTestsFound unavailable")
        return 2 // We're assuming that EXIT_SUCCESS = 0 and EXIT_FAILURE = 1.
        #endif
    }

    /// Run a process and throw a more specific error if the file doesn't exist.
    @discardableResult
    private static func runProcessWithExistenceCheck(
        path: AbsolutePath,
        fileSystem: FileSystem,
        args: [String],
        env: Environment
    ) throws -> String {
        do {
            return try AsyncProcess.checkNonZeroExit(arguments: args, environment: env)
        } catch {
            // If the file doesn't exist, throw a more specific error.
            if !fileSystem.exists(path) {
                throw FileSystemError(.noEntry, path)
            }
            throw error
        }
    }

    /// Creates the environment needed to test related tools.
    ///
    /// - Parameters:
    ///   - toolchain: Swift toolchain details.
    ///   - buildParameters: The build parameters for the destination platform.
    ///   - sanitizers: The sanitizers enabled for this test run.
    ///   - library: The testing library to configure the environment for.
    ///   - testProductPaths: Paths to the built test product bundles or executables.
    ///   - interopMode: Controls test execution default interop mode.
    ///   If set to nil, the constructed test environment will defer to Swift
    ///   Testing and XCTest's default interop mode.
    ///
    /// - Throws: If an error occurred while building the test environment.
    /// - Returns: The constructed environment.
    static func constructTestEnvironment(
        toolchain: UserToolchain,
        destinationBuildParameters buildParameters: BuildParameters,
        sanitizers: [Sanitizer],
        library: TestingLibrary,
        testProductPaths: [AbsolutePath],
        interopMode: String?
    ) throws -> Environment {
        var env = Environment.current

        // If the standard output or error stream is NOT a TTY, set the NO_COLOR
        // environment variable. This environment variable is a de facto
        // standard used to inform downstream processes not to add ANSI escape
        // codes to their output. SEE: https://www.no-color.org
        if !stdoutStream.isTTY || !stderrStream.isTTY {
            env["NO_COLOR"] = "1"
        }

        // Add library paths so that test runner executables are able to find the
        // corresponding test libraries, even if local rpaths were disabled in the
        // build.
        for path in testProductPaths {
            env.appendPath(key: .libraryPath, value: path.parentDirectory.pathString)
        }

        // Add the code coverage related variables.
        if buildParameters.testingParameters.enableCodeCoverage {
            // Defines the path at which the profraw files will be written on test execution.
            //
            // `%Nm` will create a pool of N profraw files and append the data from each execution
            // in one of the files. The runtime takes care of selecting a raw profile from the pool,
            // locking it, and updating it before the program exits. If N is not specified, it is
            // inferred to be 1.
            //
            // This is fine for parallel execution within a process, but for parallel tests, SwiftPM
            // repeatedly invokes the test binary with the testcase name as the filter and the
            // locking cannot be enforced by the runtime across the process boundaries.
            //
            // It's also possible that tests themselves will fork (e.g. for exit tests provided by
            // Swift Testing), which will inherit the environment of the parent process, and so
            // write to the same file, leading to profile data corruption.
            //
            // For these reasons, we unilaterally also add a %p, which will cause uniquely named
            // files per process.
            //
            // These are all merged using `llvm-profdata merge` once the outer test command has
            // completed.
            let codecovProfile = buildParameters.buildPath.appending(components: "codecov", "\(library)%m.%p.profraw")
            env["LLVM_PROFILE_FILE"] = codecovProfile.pathString
        }

        // Set interop mode override if user didn't explicitly set it.
        if let interopMode, env["SWIFT_TESTING_XCTEST_INTEROP_MODE"] == nil {
            env["SWIFT_TESTING_XCTEST_INTEROP_MODE"] = interopMode
        }

        #if !os(macOS)
        #if os(Windows)
        if let xctestLocation = toolchain.xctestPath {
            env.prependPath(key: .path, value: xctestLocation.pathString)
        }
        if let swiftTestingLocation = toolchain.swiftTestingPath {
            env.prependPath(key: .path, value: swiftTestingLocation.pathString)
        }
        #endif
        return env
        #else
        // Add path to swift-testing override if there is one
        if let swiftTestingPath = toolchain.swiftTestingPath {
            if swiftTestingPath.extension == "framework" {
                env.appendPath(key: "DYLD_FRAMEWORK_PATH", value: swiftTestingPath.pathString)
            } else {
                env.appendPath(key: "DYLD_LIBRARY_PATH", value: swiftTestingPath.pathString)
            }
        }

        // Add the sdk platform path if we have it.
        // Since XCTestHelper targets macOS, we need the macOS platform paths here.
        if let sdkPlatformPaths = try? SwiftSDK.sdkPlatformPaths(for: .macOS) {
            // appending since we prefer the user setting (if set) to the one we inject
            for frameworkPath in sdkPlatformPaths.runtimeFrameworkSearchPaths {
                env.appendPath(key: "DYLD_FRAMEWORK_PATH", value: frameworkPath.pathString)
            }
            for libraryPath in sdkPlatformPaths.runtimeLibrarySearchPaths {
                env.appendPath(key: "DYLD_LIBRARY_PATH", value: libraryPath.pathString)
            }
        }

        // We aren't using XCTest's harness logic to run Swift Testing tests.
        if library == .xctest {
            env["SWIFT_TESTING_ENABLED"] = "0"
        }

        // Fast path when no sanitizers are enabled.
        if sanitizers.isEmpty {
            return env
        }

        // Get the runtime libraries.
        var runtimes = try sanitizers.map({ sanitizer in
            return try toolchain.runtimeLibrary(for: sanitizer).pathString
        })

        // Append any existing value to the front.
        if let existingValue = env["DYLD_INSERT_LIBRARIES"], !existingValue.isEmpty {
            runtimes.insert(existingValue, at: 0)
        }

        env["DYLD_INSERT_LIBRARIES"] = runtimes.joined(separator: ":")
        return env
        #endif
    }
}

extension ToolsVersion {
    /// Default interop mode for this tools version.
    ///
    /// If provided, this value should be set for the
    /// `SWIFT_TESTING_XCTEST_INTEROP_MODE` environment variable.
    var defaultInteropMode: String? {
        self >= .v6_4 ? "complete" : nil
    }
}

extension SwiftCommandState {
    func buildParametersForTest(
        enableCodeCoverage: Bool,
        enableTestability: Bool? = nil,
        shouldSkipBuilding: Bool = false,
        experimentalTestOutput: Bool = false
    ) throws -> (productsBuildParameters: BuildParameters, toolsBuildParameters: BuildParameters) {
        let productsBuildParameters = buildParametersForTest(
            modifying: try productsBuildParameters,
            enableCodeCoverage: enableCodeCoverage,
            enableTestability: enableTestability,
            shouldSkipBuilding: shouldSkipBuilding,
            experimentalTestOutput: experimentalTestOutput
        )
        let toolsBuildParameters = buildParametersForTest(
            modifying: try toolsBuildParameters,
            enableCodeCoverage: enableCodeCoverage,
            enableTestability: enableTestability,
            shouldSkipBuilding: shouldSkipBuilding,
            experimentalTestOutput: experimentalTestOutput
        )
        return (productsBuildParameters, toolsBuildParameters)
    }

    private func buildParametersForTest(
        modifying parameters: BuildParameters,
        enableCodeCoverage: Bool,
        enableTestability: Bool?,
        shouldSkipBuilding: Bool,
        experimentalTestOutput: Bool
    ) -> BuildParameters {
        var parameters = parameters
        parameters.testingParameters.enableCodeCoverage = enableCodeCoverage
        // for test commands, we normally enable building with testability
        // but we let users override this with a flag
        parameters.testingParameters.explicitlyEnabledTestability = enableTestability ?? true
        parameters.shouldSkipBuilding = shouldSkipBuilding
        parameters.testingParameters.experimentalTestOutput = experimentalTestOutput
        return parameters
    }
}
