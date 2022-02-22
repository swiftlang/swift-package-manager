/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2022 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basics
import SPMBuildCore
import TSCBasic
import Workspace


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
    static func xctestHelperPath(swiftTool: SwiftTool) throws -> AbsolutePath {
        let xctestHelperBin = "swiftpm-xctest-helper"
        let binDirectory = AbsolutePath(CommandLine.arguments.first!,
            relativeTo: swiftTool.originalWorkingDirectory).parentDirectory
        // XCTestHelper tool is installed in libexec.
        let maybePath = binDirectory.parentDirectory.appending(components: "libexec", "swift", "pm", xctestHelperBin)
        if swiftTool.fileSystem.isFile(maybePath) {
            return maybePath
        }
        // This will be true during swiftpm development.
        // FIXME: Factor all of the development-time resource location stuff into a common place.
        let path = binDirectory.appending(component: xctestHelperBin)
        if swiftTool.fileSystem.isFile(path) {
            return path
        }
        throw InternalError("XCTestHelper binary not found.")
    }

    static func getTestSuites(in testProducts: [BuiltTestProduct], swiftTool: SwiftTool, swiftOptions: SwiftToolOptions) throws -> [AbsolutePath: [TestSuite]] {
        let testSuitesByProduct = try testProducts
            .map { try ($0.bundlePath, TestingSupport.getTestSuites(fromTestAt: $0.bundlePath, swiftTool: swiftTool, swiftOptions: swiftOptions)) }
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
    static func getTestSuites(fromTestAt path: AbsolutePath, swiftTool: SwiftTool, swiftOptions: SwiftToolOptions) throws -> [TestSuite] {
        // Run the correct tool.
        #if os(macOS)
        let data: String = try withTemporaryFile { tempFile in
            let args = [try TestingSupport.xctestHelperPath(swiftTool: swiftTool).pathString, path.pathString, tempFile.path.pathString]
            var env = try TestingSupport.constructTestEnvironment(toolchain: try swiftTool.getToolchain(), options: swiftOptions, buildParameters: swiftTool.buildParametersForTest())
            // Add the sdk platform path if we have it. If this is not present, we
            // might always end up failing.
            if let sdkPlatformFrameworksPath = Destination.sdkPlatformFrameworkPaths() {
                // appending since we prefer the user setting (if set) to the one we inject
                env.appendPath("DYLD_FRAMEWORK_PATH", value: sdkPlatformFrameworksPath.fwk.pathString)
                env.appendPath("DYLD_LIBRARY_PATH", value: sdkPlatformFrameworksPath.lib.pathString)
            }
            try Process.checkNonZeroExit(arguments: args, environment: env)
            // Read the temporary file's content.
            return try swiftTool.fileSystem.readFileContents(tempFile.path)
        }
        #else
        let env = try constructTestEnvironment(toolchain: try swiftTool.getToolchain(), options: swiftOptions, buildParameters: swiftTool.buildParametersForTest())
        let args = [path.description, "--dump-tests-json"]
        let data = try Process.checkNonZeroExit(arguments: args, environment: env)
        #endif
        // Parse json and return TestSuites.
        return try TestSuite.parse(jsonString: data)
    }

    /// Creates the environment needed to test related tools.
    static func constructTestEnvironment(
        toolchain: UserToolchain,
        options: SwiftToolOptions,
        buildParameters: BuildParameters
    ) throws -> EnvironmentVariables {
        var env = EnvironmentVariables.process()

        // Add the code coverage related variables.
        if options.shouldEnableCodeCoverage {
            // Defines the path at which the profraw files will be written on test execution.
            //
            // `%m` will create a pool of profraw files and append the data from
            // each execution in one of the files. This doesn't matter for serial
            // execution but is required when the tests are running in parallel as
            // SwiftPM repeatedly invokes the test binary with the test case name as
            // the filter.
            let codecovProfile = buildParameters.buildPath.appending(components: "codecov", "default%m.profraw")
            env["LLVM_PROFILE_FILE"] = codecovProfile.pathString
        }
        #if !os(macOS)
        #if os(Windows)
        if let location = toolchain.configuration.xctestPath {
            env.prependPath("Path", value: location.pathString)
        }
        #endif
        return env
        #else
        // Fast path when no sanitizers are enabled.
        if options.sanitizers.isEmpty {
            return env
        }

        // Get the runtime libraries.
        var runtimes = try options.sanitizers.map({ sanitizer in
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

extension SwiftTool {
    func buildParametersForTest(
        enableTestability: Bool? = nil
    ) throws -> BuildParameters {
        var parameters = try self.buildParameters()
        // for test commands, we normally enable building with testability
        // but we let users override this with a flag
        parameters.enableTestability = enableTestability ?? true
        return parameters
    }
}
