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
import Foundation
import PackageModel
import SPMBuildCore
import TSCUtility
import Workspace

#if canImport(WinSDK)
import WinSDK
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

import struct TSCBasic.FileSystemError
import class Basics.AsyncProcess
import var TSCBasic.stderrStream
import var TSCBasic.stdoutStream
import func TSCBasic.withTemporaryFile
import func TSCBasic.exec

struct DebuggableTestSession {
    struct Target {
        let library: TestingLibrary
        let additionalArgs: [String]
        let bundlePath: AbsolutePath
    }

    let targets: [Target]

    /// Whether this is part of a multi-session sequence
    var isMultiSession: Bool {
        targets.count > 1
    }
}

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
                library: .xctest
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
            library: .xctest
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
    static func constructTestEnvironment(
        toolchain: UserToolchain,
        destinationBuildParameters buildParameters: BuildParameters,
        sanitizers: [Sanitizer],
        library: TestingLibrary
    ) throws -> Environment {
        var env = Environment.current

        // If the standard output or error stream is NOT a TTY, set the NO_COLOR
        // environment variable. This environment variable is a de facto
        // standard used to inform downstream processes not to add ANSI escape
        // codes to their output. SEE: https://www.no-color.org
        if !stdoutStream.isTTY || !stderrStream.isTTY {
            env["NO_COLOR"] = "1"
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

/// A class to run tests under LLDB debugger.
final class DebugTestRunner {
    private let target: DebuggableTestSession
    private let buildParameters: BuildParameters
    private let toolchain: UserToolchain
    private let testEnv: Environment
    private let cancellator: Cancellator
    private let fileSystem: FileSystem
    private let observabilityScope: ObservabilityScope
    private let verbose: Bool

    /// Creates an instance of debug test runner.
    init(
        target: DebuggableTestSession,
        buildParameters: BuildParameters,
        toolchain: UserToolchain,
        testEnv: Environment,
        cancellator: Cancellator,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        verbose: Bool = false
    ) {
        self.target = target
        self.buildParameters = buildParameters
        self.toolchain = toolchain
        self.testEnv = testEnv
        self.cancellator = cancellator
        self.fileSystem = fileSystem
        self.observabilityScope = observabilityScope
        self.verbose = verbose
    }

    /// Launches the test binary under LLDB for interactive debugging.
    ///
    /// This method:
    /// 1. Discovers LLDB using the toolchain
    /// 2. Configures the environment for debugging
    /// 3. Launches LLDB with the proper test runner as target
    /// 4. Provides interactive debugging experience through appropriate process management
    ///
    /// **Implementation approach varies by testing library:**
    /// - **XCTest**: Uses PTY (pseudo-terminal) via `runInPty()` to support LLDB's full-screen
    ///   terminal features while maintaining parent process control for sequential execution
    /// - **Swift Testing**: Uses `exec()` to replace the current process (works because Swift Testing
    ///   is always the last library in the sequence, avoiding the need for sequential execution)
    ///
    /// The PTY approach is necessary for XCTest because LLDB requires advanced terminal features
    /// (ANSI escape sequences, raw input mode, terminal sizing) that simple stdin/stdout redirection
    /// cannot provide, while still allowing the parent process to show completion messages and
    /// run multiple testing libraries sequentially.
    ///
    /// **Test Mode**: When running Swift Package Manager's own tests (detected via environment variables),
    /// this method uses `AsyncProcess` instead of `exec()` to launch LLDB as a subprocess without stdin.
    /// This allows the parent test process to capture LLDB's output for validation while ensuring LLDB
    /// exits immediately due to lack of interactive input.
    ///
    /// - Throws: Various errors if LLDB cannot be found or launched
    func run() throws {
        let lldbPath: AbsolutePath
        do {
            lldbPath = try toolchain.getLLDB()
        } catch {
            observabilityScope.emit(error: "LLDB not found in toolchain: \(error)")
            throw error
        }

        let lldbArgs = try prepareLLDBArguments(for: target)
        observabilityScope.emit(info: "LLDB will run: \(lldbPath.pathString) \(lldbArgs.joined(separator: " "))")

        // Set environment variables from testEnv on the current process
        // so they are inherited by the exec'd LLDB process. Exec will replace
        // this process.
        for (key, value) in testEnv {
            try Environment.set(key: key, value: value)
        }

        // Check if we're running Swift Package Manager's own tests
        let isRunningTests = Environment.current["SWIFTPM_TESTS_LLDB"] != nil

        if isRunningTests {
            // When running tests, use AsyncProcess to launch LLDB as a subprocess
            // This allows the test to capture output while LLDB exits due to no stdin
            try runLLDBForTesting(lldbPath: lldbPath, args: lldbArgs)
        } else {
            // Normal interactive mode - use exec to replace the current process with LLDB
            // This avoids PTY issues that interfere with LLDB's command line editing
            try exec(path: lldbPath.pathString, args: [lldbPath.pathString] + lldbArgs)
        }
    }

    /// Launches LLDB as a subprocess for testing purposes.
    ///
    /// This method is used when running Swift Package Manager's own tests to validate
    /// debugger functionality. It launches LLDB without stdin attached, which causes
    /// LLDB to execute its startup commands and then exit, allowing the test to capture
    /// and validate the output.
    ///
    /// - Parameters:
    ///   - lldbPath: Path to the LLDB executable
    ///   - args: Command line arguments for LLDB
    /// - Throws: Process execution errors
    private func runLLDBForTesting(lldbPath: AbsolutePath, args: [String]) throws {
        let process = AsyncProcess(
            arguments: [lldbPath.pathString] + args,
            environment: testEnv,
            outputRedirection: .collect
        )

        try process.launch()
        let result = try process.waitUntilExit()

        // Print the output so tests can capture it
        if let stdout = try? result.utf8Output() {
            print(stdout, terminator: "")
        }
        if let stderr = try? result.utf8stderrOutput() {
            print(stderr, terminator: "")
        }

        // Exit with the same code as LLDB to indicate success/failure
        switch result.exitStatus {
        case .terminated(let code):
            if code != 0 {
                throw AsyncProcessResult.Error.nonZeroExit(result)
            }
        default:
            throw AsyncProcessResult.Error.nonZeroExit(result)
        }
    }

    /// Returns the path to the Python script file.
    private func pythonScriptFilePath() throws -> AbsolutePath {
        let tempDir = try fileSystem.tempDirectory
        return tempDir.appending("target_switcher.py")
    }

    /// Prepares LLDB arguments for debugging based on the testing library.
    ///
    /// This method creates a temporary LLDB command file with the necessary setup commands
    /// for debugging tests, including target creation, argument configuration, and symbol loading.
    ///
    /// - Parameter library: The testing library being used (XCTest or Swift Testing)
    /// - Returns: Array of LLDB command line arguments
    /// - Throws: Various errors if required tools are not found or file operations fail
    private func prepareLLDBArguments(for target: DebuggableTestSession) throws -> [String] {
        let tempDir = try fileSystem.tempDirectory
        let lldbCommandFile = tempDir.appending("lldb-commands.txt")

        var lldbCommands: [String] = []
        if target.isMultiSession {
            try setupMultipleTargets(&lldbCommands)
        } else if let library = target.targets.first {
            try setupSingleTarget(&lldbCommands, for: library)
        } else {
            throw StringError("No testing libraries found for debugging")
        }

        // Clear the screen of all the previous commands to unclutter the users initial state.
        // Skip clearing in verbose mode so startup commands remain visible
        if !verbose {
            lldbCommands.append("script print(\"\\033[H\\033[J\", end=\"\")")
        }

        let commandScript = lldbCommands.joined(separator: "\n")
        try fileSystem.writeFileContents(lldbCommandFile, string: commandScript)

        // Return script file arguments without batch mode to allow interactive debugging
        return ["-s", lldbCommandFile.pathString]
    }

    /// Sets up multiple targets when both XCTest and Swift Testing are available
    private func setupMultipleTargets(_ lldbCommands: inout [String]) throws {
        var hasSwiftTesting = false
        var hasXCTest = false

        for testingLibrary in target.targets {
            let (executable, args) = try getExecutableAndArgs(for: testingLibrary)
            lldbCommands.append("target create \(executable.pathString)")
            lldbCommands.append("settings clear target.run-args")

            for arg in args {
                lldbCommands.append("settings append target.run-args \"\(arg)\"")
            }

            let modulePath = getModulePath(for: testingLibrary)
            lldbCommands.append("target modules add \"\(modulePath.pathString)\"")

            if testingLibrary.library == .swiftTesting {
                hasSwiftTesting = true
            } else if testingLibrary.library == .xctest {
                hasXCTest = true
            }
        }

        setupCommandAliases(&lldbCommands, hasSwiftTesting: hasSwiftTesting, hasXCTest: hasXCTest)

        // Create the target switching Python script
        let scriptPath = try createTargetSwitchingScript()
        lldbCommands.append("command script import \"\(scriptPath.pathString)\"")

        // Select the first target and launch with pause on main
        lldbCommands.append("target select 0")
    }

    /// Sets up a single target when only one testing library is available
    private func setupSingleTarget(_ lldbCommands: inout [String], for target: DebuggableTestSession.Target) throws {
        let (executable, args) = try getExecutableAndArgs(for: target)
        // Create target
        lldbCommands.append("target create \(executable.pathString)")
        lldbCommands.append("settings clear target.run-args")

        // Add arguments
        for arg in args {
            lldbCommands.append("settings append target.run-args \"\(arg)\"")
        }

        // Load symbols for the test bundle
        let modulePath = getModulePath(for: target)
        lldbCommands.append("target modules add \"\(modulePath.pathString)\"")

        setupCommandAliases(&lldbCommands, hasSwiftTesting: target.library == .swiftTesting, hasXCTest: target.library == .xctest)
    }

    private func setupCommandAliases(_ lldbCommands: inout [String], hasSwiftTesting: Bool, hasXCTest: Bool) {
        #if os(macOS)
            let swiftTestingFailureBreakpoint = "-s Testing -n \"failureBreakpoint()\""
            let xctestFailureBreakpoint = "-n \"_XCTFailureBreakpoint\""
        #elseif os(Windows)
            let swiftTestingFailureBreakpoint = "-s Testing.dll -n \"failureBreakpoint()\""
            let xctestFailureBreakpoint = "-s XCTest.dll -n \"XCTest.XCTestCase.recordFailure\""
        #else
            let swiftTestingFailureBreakpoint = "-s libTesting.so -n \"Testing.failureBreakpoint\""
            let xctestFailureBreakpoint = "-s libXCTest.so -n \"XCTest.XCTestCase.recordFailure\""
        #endif

        // Add clear screen alias
        lldbCommands.append("command alias clear script print(\"\\033[H\\033[J\", end=\"\")")

        // Add failure breakpoint commands based on available libraries
        if hasSwiftTesting && hasXCTest {
            lldbCommands.append("command alias failbreak script lldb.debugger.HandleCommand('breakpoint set \(swiftTestingFailureBreakpoint)'); lldb.debugger.HandleCommand('breakpoint set \(xctestFailureBreakpoint)')")
        } else if hasSwiftTesting {
            lldbCommands.append("command alias failbreak breakpoint set \(swiftTestingFailureBreakpoint)")
        } else if hasXCTest {
            lldbCommands.append("command alias failbreak breakpoint set \(xctestFailureBreakpoint)")
        }
    }

    /// Gets the executable path and arguments for a given testing library
    private func getExecutableAndArgs(for target: DebuggableTestSession.Target) throws -> (AbsolutePath, [String]) {
        switch target.library {
        case .xctest:
            #if os(macOS)
            guard let xctestPath = toolchain.xctestPath else {
                throw StringError("XCTest not found in toolchain")
            }
            return (xctestPath, [target.bundlePath.pathString] + target.additionalArgs)
            #else
            return (target.bundlePath, target.additionalArgs)
            #endif
        case .swiftTesting:
            #if os(macOS)
            let executable = try toolchain.getSwiftTestingHelper()
            let args = ["--test-bundle-path", target.bundlePath.pathString] + target.additionalArgs
            #else
            let executable = target.bundlePath
            let args = target.additionalArgs
            #endif
            return (executable, args)
        }
    }

    /// Gets the module path for symbol loading
    private func getModulePath(for target: DebuggableTestSession.Target) -> AbsolutePath {
        var modulePath = target.bundlePath
        if target.library == .xctest && buildParameters.triple.isDarwin() {
            if let name = target.bundlePath.components.last?.replacing(".xctest", with: "") {
                if let relativePath = try? RelativePath(validating: "Contents/MacOS/\(name)") {
                    modulePath = target.bundlePath.appending(relativePath)
                }
            }
        }
        return modulePath
    }

    /// Creates a Python script that handles automatic target switching
    private func createTargetSwitchingScript() throws -> AbsolutePath {
        let scriptPath = try pythonScriptFilePath()

        let pythonScript = """
# target_switcher.py
import lldb
import threading
import time
import sys

current_target_index = 0
max_targets = 0
debugger_ref = None
known_breakpoints = set()
sequence_active = True  # Start active by default

def sync_breakpoints_to_target(source_target, dest_target):
    \"\"\"Synchronize breakpoints from source target to destination target.\"\"\"
    if not source_target or not dest_target:
        return

    def breakpoint_exists_in_target_by_spec(target, file_name, line_number, function_name):
        \"\"\"Check if a breakpoint already exists in the target by specification.\"\"\"
        for i in range(target.GetNumBreakpoints()):
            existing_bp = target.GetBreakpointAtIndex(i)
            if not existing_bp.IsValid():
                continue

            # Check function name breakpoints
            if function_name:
                # Get the breakpoint's function name specifications
                names = lldb.SBStringList()
                existing_bp.GetNames(names)

                # Check names from GetNames()
                for j in range(names.GetSize()):
                    if names.GetStringAtIndex(j) == function_name:
                        return True

                # If no names found, check the description for pending breakpoints
                if names.GetSize() == 0:
                    bp_desc = str(existing_bp).strip()
                    import re
                    match = re.search(r"name = '([^']+)'", bp_desc)
                    if match and match.group(1) == function_name:
                        return True

            # Check file/line breakpoints (only if resolved)
            if file_name and line_number:
                for j in range(existing_bp.GetNumLocations()):
                    location = existing_bp.GetLocationAtIndex(j)
                    if location.IsValid():
                        addr = location.GetAddress()
                        line_entry = addr.GetLineEntry()
                        if line_entry.IsValid():
                            existing_file_spec = line_entry.GetFileSpec()
                            existing_line_number = line_entry.GetLine()
                            if (existing_file_spec.GetFilename() == file_name and
                                existing_line_number == line_number):
                                return True
        return False

    # Get all breakpoints from source target
    for i in range(source_target.GetNumBreakpoints()):
        bp = source_target.GetBreakpointAtIndex(i)
        if not bp.IsValid():
            continue

        # Handle breakpoints by their specifications, not just resolved locations
        # First check if this is a function name breakpoint
        names = lldb.SBStringList()
        bp.GetNames(names)

        # For pending breakpoints, GetNames() might be empty, so also check the description
        bp_desc = str(bp).strip()

        # Extract function name from description if names is empty
        function_names_to_sync = []
        if names.GetSize() > 0:
            # Use the names from GetNames()
            for j in range(names.GetSize()):
                function_name = names.GetStringAtIndex(j)
                if function_name:
                    function_names_to_sync.append(function_name)
        else:
            # Parse function name from description for pending breakpoints
            # Description format: "1: name = 'failureBreakpoint()', module = Testing, locations = 0 (pending)"
            import re
            match = re.search(r"name = '([^']+)'", bp_desc)
            if match:
                function_name = match.group(1)
                function_names_to_sync.append(function_name)

        # Sync the function name breakpoints
        for function_name in function_names_to_sync:
            if not breakpoint_exists_in_target_by_spec(dest_target, None, None, function_name):
                new_bp = dest_target.BreakpointCreateByName(function_name)
                if new_bp.IsValid():
                    new_bp.SetEnabled(bp.IsEnabled())
                    new_bp.SetCondition(bp.GetCondition())
                    new_bp.SetIgnoreCount(bp.GetIgnoreCount())

        # Handle resolved location-based breakpoints (file/line)
        # Only process if the breakpoint has resolved locations
        if bp.GetNumLocations() > 0:
            for j in range(bp.GetNumLocations()):
                location = bp.GetLocationAtIndex(j)
                if not location.IsValid():
                    continue

                addr = location.GetAddress()
                line_entry = addr.GetLineEntry()

                if line_entry.IsValid():
                    file_spec = line_entry.GetFileSpec()
                    line_number = line_entry.GetLine()
                    file_name = file_spec.GetFilename()

                    # Check if this breakpoint already exists in destination target
                    if breakpoint_exists_in_target_by_spec(dest_target, file_name, line_number, None):
                        continue

                    # Create the same breakpoint in the destination target
                    new_bp = dest_target.BreakpointCreateByLocation(file_spec, line_number)
                    if new_bp.IsValid():
                        # Copy breakpoint properties
                        new_bp.SetEnabled(bp.IsEnabled())
                        new_bp.SetCondition(bp.GetCondition())
                        new_bp.SetIgnoreCount(bp.GetIgnoreCount())

def sync_breakpoints_to_all_targets():
    \"\"\"Synchronize breakpoints from current target to all other targets.\"\"\"
    global debugger_ref, max_targets

    if not debugger_ref or max_targets <= 1:
        return

    current_target = debugger_ref.GetSelectedTarget()
    if not current_target:
        return

    # Sync to all other targets
    for i in range(max_targets):
        target = debugger_ref.GetTargetAtIndex(i)
        if target and target != current_target:
            sync_breakpoints_to_target(current_target, target)

def monitor_breakpoints():
    \"\"\"Monitor breakpoint changes and sync them across targets.\"\"\"
    global debugger_ref, known_breakpoints, max_targets

    if max_targets <= 1:
        return

    last_breakpoint_count = 0

    while True:  # Keep running forever, not just while current_target_index < max_targets
        if debugger_ref:
            current_target = debugger_ref.GetSelectedTarget()
            if current_target:
                current_bp_count = current_target.GetNumBreakpoints()

                # If breakpoint count changed, sync to all targets
                if current_bp_count != last_breakpoint_count:
                    sync_breakpoints_to_all_targets()
                    last_breakpoint_count = current_bp_count

        time.sleep(0.5)  # Check every 500ms

def check_process_status():
    \"\"\"Periodically check if the current process has exited.\"\"\"
    global current_target_index, max_targets, debugger_ref, sequence_active

    while True:  # Keep running forever, don't exit
        if debugger_ref:
            target = debugger_ref.GetSelectedTarget()
            if target:
                process = target.GetProcess()
                if process and process.GetState() == lldb.eStateExited:
                    # Process has exited
                    if sequence_active and current_target_index < max_targets:
                        # We're in an active sequence, trigger switch
                        current_target_index += 1

                        if current_target_index < max_targets:
                            # Switch to next target and launch immediately
                            print("\\n")
                            debugger_ref.HandleCommand(f'target select {current_target_index}')
                            print(" ")

                            # Get target name for user feedback
                            new_target = debugger_ref.GetSelectedTarget()
                            target_name = new_target.GetExecutable().GetFilename() if new_target else "Unknown"

                            # Launch the next target immediately with pause on main
                            debugger_ref.HandleCommand('process launch') # -m to pause on main
                        else:
                            # Reset to first target and deactivate sequence until user runs again
                            current_target_index = 0
                            sequence_active = False  # Pause automatic switching

                            print("\\n")
                            debugger_ref.HandleCommand('target select 0')
                            print("\\nAll testing targets completed.")
                            print("Type 'run' to restart the entire test sequence from the beginning.\\n")

                            # Clear the current line and move cursor to start
                            sys.stdout.write("\\033[2K\\r")
                            # Reprint a fake prompt
                            sys.stdout.write("(lldb) ")
                            sys.stdout.flush()
                elif process and process.GetState() in [lldb.eStateRunning, lldb.eStateLaunching]:
                    # Process is running - if sequence was inactive, reactivate it
                    if not sequence_active:
                        sequence_active = True
                        # Find which target is currently selected to set the correct index
                        selected_target = debugger_ref.GetSelectedTarget()
                        if selected_target:
                            for i in range(max_targets):
                                if debugger_ref.GetTargetAtIndex(i) == selected_target:
                                    current_target_index = i
                                    break

        time.sleep(0.1)  # Check every second

def __lldb_init_module(debugger, internal_dict):
    global max_targets, debugger_ref

    debugger_ref = debugger

    # Count the number of targets
    max_targets = debugger.GetNumTargets()

    if max_targets > 1:
        # Start the process status checker
        status_thread = threading.Thread(target=check_process_status, daemon=True)
        status_thread.start()

        # Start the breakpoint monitor
        bp_thread = threading.Thread(target=monitor_breakpoints, daemon=True)
        bp_thread.start()
"""

        try fileSystem.writeFileContents(scriptPath, string: pythonScript)
        return scriptPath
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
