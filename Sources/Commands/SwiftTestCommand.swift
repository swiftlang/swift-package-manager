//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2015-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParser

@_spi(SwiftPMInternal)
import Basics

import _Concurrency

@_spi(SwiftPMInternal)
import CoreCommands

import Dispatch
import Foundation
import PackageGraph

@_spi(SwiftPMInternal)
import PackageModel

import SPMBuildCore
import TSCUtility

import func TSCLibc.exit
import Workspace

import class Basics.AsyncProcess
import struct TSCBasic.ByteString
import struct TSCBasic.FileSystemError
import enum TSCBasic.JSON
import var TSCBasic.stdoutStream
import class TSCBasic.SynchronizedQueue
import class TSCBasic.Thread

#if os(Windows)
import WinSDK // for ERROR_NOT_FOUND
#elseif canImport(Android)
import Android
#endif

private enum TestError: Swift.Error {
    case invalidListTestJSONData(context: String, underlyingError: Error? = nil)
    case testsNotFound
    case testProductNotFound(productName: String)
    case productIsNotTest(productName: String)
    case multipleTestProducts([String])
    case xctestNotAvailable(reason: String)
    case xcodeNotInstalled
}

extension TestError: CustomStringConvertible {
    var description: String {
        switch self {
        case .testsNotFound:
            return "no tests found; create a target in the 'Tests' directory"
        case .testProductNotFound(let productName):
            return "there is no test product named '\(productName)'"
        case .productIsNotTest(let productName):
            return "the product '\(productName)' is not a test"
        case .invalidListTestJSONData(let context, let underlyingError):
            let underlying = underlyingError != nil ? ", underlying error: \(underlyingError!)" : ""
            return "invalid list test JSON structure, produced by \(context)\(underlying)"
        case .multipleTestProducts(let products):
            return "found multiple test products: \(products.joined(separator: ", ")); use --test-product to select one"
        case let .xctestNotAvailable(reason):
            return "XCTest not available: \(reason)"
        case .xcodeNotInstalled:
            return "XCTest not available; download and install Xcode to use XCTest on this platform"
        }
    }
}

struct SharedOptions: ParsableArguments {
    @Flag(name: .customLong("skip-build"),
          help: "Skip building the test target")
    var shouldSkipBuilding: Bool = false

    /// The test product to use. This is useful when there are multiple test products
    /// to choose from (usually in multiroot packages).
    @Option(help: .hidden)
    var testProduct: String?
}

struct TestEventStreamOptions: ParsableArguments {
    /// Legacy equivalent of ``configurationPath``.
    @Option(name: .customLong("experimental-configuration-path"),
            help: .private)
    var experimentalConfigurationPath: AbsolutePath?

    /// Path where swift-testing's JSON configuration should be read.
    @Option(name: .customLong("configuration-path"),
            help: .hidden)
    var configurationPath: AbsolutePath?

    /// Legacy equivalent of ``eventStreamOutputPath``.
    @Option(name: .customLong("experimental-event-stream-output"),
            help: .private)
    var experimentalEventStreamOutputPath: AbsolutePath?

    /// Path where swift-testing's JSON output should be written.
    @Option(name: .customLong("event-stream-output-path"),
            help: .hidden)
    var eventStreamOutputPath: AbsolutePath?

    /// Legacy equivalent of ``eventStreamVersion``.
    @Option(name: .customLong("experimental-event-stream-version"),
            help: .private)
    var experimentalEventStreamVersion: Int?

    /// The schema version of swift-testing's JSON input/output.
    @Option(name: .customLong("event-stream-version"),
            help: .hidden)
    var eventStreamVersion: Int?

    /// Experimental path for writing attachments (Swift Testing only.)
    @Option(name: .customLong("experimental-attachments-path"),
            help: .private)
    var experimentalAttachmentsPath: AbsolutePath?

    /// Path for writing attachments (Swift Testing only.)
    @Option(name: .customLong("attachments-path"),
            help: "Path where attachments should be written (Swift Testing only). This path must be an existing directory the current user can write to. If not specified, any attachments created during testing are discarded.")
    var attachmentsPath: AbsolutePath?
}

struct TestCommandOptions: ParsableArguments {
    @OptionGroup()
    var globalOptions: GlobalOptions

    @OptionGroup()
    var sharedOptions: SharedOptions

    /// Which testing libraries to use (and any related options.)
    @OptionGroup()
    var testLibraryOptions: TestLibraryOptions

    /// Options for Swift Testing's event stream.
    @OptionGroup()
    var testEventStreamOptions: TestEventStreamOptions

    /// If tests should run in parallel mode.
    @Flag(name: .customLong("parallel"),
          inversion: .prefixedNo,
          help: "Run the tests in parallel.")
    var shouldRunInParallel: Bool = false

    /// Number of tests to execute in parallel
    @Option(name: .customLong("num-workers"),
            help: "Number of tests to execute in parallel.")
    var numberOfWorkers: Int?

    /// List the tests and exit.
    @Flag(name: [.customLong("list-tests"), .customShort("l")],
          help: "Lists test methods in specifier format")
    var _deprecated_shouldListTests: Bool = false

    /// If the path of the exported code coverage JSON should be printed.
    @Flag(name: [.customLong("show-codecov-path"), .customLong("show-code-coverage-path"), .customLong("show-coverage-path")],
          help: "Print the path of the exported code coverage JSON file")
    var shouldPrintCodeCovPath: Bool = false

    var testCaseSpecifier: TestCaseSpecifier {
        if !filter.isEmpty {
            return .regex(filter)
        }

        return _testCaseSpecifier.map { .specific($0) } ?? .none
    }

    @Option(name: [.customShort("s"), .customLong("specifier")])
    var _testCaseSpecifier: String?

    @Option(help: """
        Run test cases matching regular expression, Format: <test-target>.<test-case> \
        or <test-target>.<test-case>/<test>
        """)
    var filter: [String] = []

    @Option(name: .customLong("skip"),
            help: "Skip test cases matching regular expression, Example: --skip PerformanceTests")
    var _testCaseSkip: [String] = []

    /// Path where the xUnit xml file should be generated.
    @Option(name: .customLong("xunit-output"),
            help: "Path where the xUnit xml file should be generated.")
    var xUnitOutput: AbsolutePath?

    @Flag(
        name: .customLong("experimental-xunit-message-failure"),
        help: ArgumentHelp(
            "When set, include the content of stdout/stderr in failure messages (XCTest only, experimental).",
            visibility: .hidden
        )
    )
    var shouldShowDetailedFailureMessage: Bool = false

    /// Generate LinuxMain entries and exit.
    @Flag(name: .customLong("testable-imports"), inversion: .prefixedEnableDisable, help: "Enable or disable testable imports. Enabled by default.")
    var enableTestableImports: Bool = true

    /// Whether to enable code coverage.
    @Flag(name: .customLong("code-coverage"),
          inversion: .prefixedEnableDisable,
          help: "Enable code coverage")
    var enableCodeCoverage: Bool = false

    /// Configure test output.
    @Option(help: ArgumentHelp("", visibility: .hidden))
    public var testOutput: TestOutput = .default

    var enableExperimentalTestOutput: Bool {
        return testOutput == .experimentalSummary
    }

    @OptionGroup(visibility: .hidden)
    package var traits: TraitOptions
}

/// Tests filtering specifier, which is used to filter tests to run.
public enum TestCaseSpecifier {
    /// No filtering
    case none

    /// Specify test with fully quantified name
    case specific(String)

    /// RegEx patterns for tests to run
    case regex([String])

    /// RegEx patterns for tests to skip
    case skip([String])
}

/// Different styles of test output.
public enum TestOutput: String, ExpressibleByArgument {
    /// Whatever `xctest` emits to the console.
    case `default`

    /// Capture XCTest events and provide a summary.
    case experimentalSummary

    /// Let the test process emit parseable output to the console.
    case experimentalParseable
}

/// swift-test tool namespace
public struct SwiftTestCommand: AsyncSwiftCommand {
    public static var configuration = CommandConfiguration(
        commandName: "test",
        _superCommandName: "swift",
        abstract: "Build and run tests",
        discussion: "SEE ALSO: swift build, swift run, swift package",
        version: SwiftVersion.current.completeDisplayString,
        subcommands: [
            List.self, Last.self
        ],
        helpNames: [.short, .long, .customLong("help", withSingleDash: true)])

    public var globalOptions: GlobalOptions {
        options.globalOptions
    }

    @OptionGroup()
    var options: TestCommandOptions

    private func run(_ swiftCommandState: SwiftCommandState, buildParameters: BuildParameters, testProducts: [BuiltTestProduct]) async throws {
        // Remove test output from prior runs and validate priors.
        if self.options.enableExperimentalTestOutput && buildParameters.triple.supportsTestSummary {
            _ = try? localFileSystem.removeFileTree(buildParameters.testOutputPath)
        }

        var results = [TestRunner.Result]()

        // Run XCTest.
        if options.testLibraryOptions.isEnabled(.xctest, swiftCommandState: swiftCommandState) {
            // Validate XCTest is available on Darwin-based systems. If it's not available and we're hitting this code
            // path, that means the developer must have explicitly passed --enable-xctest (or the toolchain is
            // corrupt, I suppose.)
            let toolchain = try swiftCommandState.getTargetToolchain()
            if case let .unsupported(reason) = try swiftCommandState.getHostToolchain().swiftSDK.xctestSupport {
                if let reason {
                    throw TestError.xctestNotAvailable(reason: reason)
                } else {
                    throw TestError.xcodeNotInstalled
                }
            } else if toolchain.targetTriple.isDarwin() && toolchain.xctestPath == nil {
                throw TestError.xcodeNotInstalled
            }

            if !self.options.shouldRunInParallel {
                let (xctestArgs, testCount) = try xctestArgs(for: testProducts, swiftCommandState: swiftCommandState)
                let result = try await runTestProducts(
                    testProducts,
                    additionalArguments: xctestArgs,
                    productsBuildParameters: buildParameters,
                    swiftCommandState: swiftCommandState,
                    library: .xctest
                )
                if result == .success, testCount == 0 {
                    results.append(.noMatchingTests)
                } else {
                    results.append(result)
                }
            } else {
                let testSuites = try TestingSupport.getTestSuites(
                    in: testProducts,
                    swiftCommandState: swiftCommandState,
                    enableCodeCoverage: options.enableCodeCoverage,
                    shouldSkipBuilding: options.sharedOptions.shouldSkipBuilding,
                    experimentalTestOutput: options.enableExperimentalTestOutput,
                    sanitizers: globalOptions.build.sanitizers
                )
                let tests = try testSuites
                    .filteredTests(specifier: options.testCaseSpecifier)
                    .skippedTests(specifier: options.skippedTests(fileSystem: swiftCommandState.fileSystem))

                let result: TestRunner.Result
                let testResults: [ParallelTestRunner.TestResult]
                if tests.isEmpty {
                    testResults = []
                    result = .noMatchingTests
                } else {
                    // Run the tests using the parallel runner.
                    let runner = ParallelTestRunner(
                        bundlePaths: testProducts.map { $0.bundlePath },
                        cancellator: swiftCommandState.cancellator,
                        toolchain: toolchain,
                        numJobs: options.numberOfWorkers ?? ProcessInfo.processInfo.activeProcessorCount,
                        buildOptions: globalOptions.build,
                        productsBuildParameters: buildParameters,
                        shouldOutputSuccess: swiftCommandState.logLevel <= .info,
                        observabilityScope: swiftCommandState.observabilityScope
                    )

                    testResults = try runner.run(tests)
                    result = runner.ranSuccessfully ? .success : .failure
                }

                try generateXUnitOutputIfRequested(for: testResults, swiftCommandState: swiftCommandState)
                results.append(result)
            }
        }

        // Run Swift Testing (parallel or not, it has a single entry point.)
        if options.testLibraryOptions.isEnabled(.swiftTesting, swiftCommandState: swiftCommandState) {
            lazy var testEntryPointPath = testProducts.lazy.compactMap(\.testEntryPointPath).first
            if options.testLibraryOptions.isExplicitlyEnabled(.swiftTesting, swiftCommandState: swiftCommandState) || testEntryPointPath == nil {
                results.append(
                    try await runTestProducts(
                        testProducts,
                        additionalArguments: [],
                        productsBuildParameters: buildParameters,
                        swiftCommandState: swiftCommandState,
                        library: .swiftTesting
                    )
                )
            } else if let testEntryPointPath {
                // Cannot run Swift Testing because an entry point file was used and the developer
                // didn't explicitly enable Swift Testing.
                swiftCommandState.observabilityScope.emit(
                    debug: "Skipping automatic Swift Testing invocation because a test entry point path is present: \(testEntryPointPath)"
                )
            }
        }

        switch results.reduce() {
        case .success:
            // Nothing to do here.
            break
        case .failure:
            swiftCommandState.executionStatus = .failure
            if self.options.enableExperimentalTestOutput {
                try Self.handleTestOutput(productsBuildParameters: buildParameters, packagePath: testProducts[0].packagePath)
            }
        case .noMatchingTests:
            swiftCommandState.observabilityScope.emit(.noMatchingTests)
        }
    }

    private func xctestArgs(for testProducts: [BuiltTestProduct], swiftCommandState: SwiftCommandState) throws -> (arguments: [String], testCount: Int?) {
        switch options.testCaseSpecifier {
        case .none:
            if case .skip = options.skippedTests(fileSystem: swiftCommandState.fileSystem) {
                fallthrough
            } else {
                return ([], nil)
            }

        case .regex, .specific, .skip:
            // If old specifier `-s` option was used, emit deprecation notice.
            if case .specific = options.testCaseSpecifier {
                swiftCommandState.observabilityScope.emit(warning: "'--specifier' option is deprecated; use '--filter' instead")
            }

            // Find the tests we need to run.
            let testSuites = try TestingSupport.getTestSuites(
                in: testProducts,
                swiftCommandState: swiftCommandState,
                enableCodeCoverage: options.enableCodeCoverage,
                shouldSkipBuilding: options.sharedOptions.shouldSkipBuilding,
                experimentalTestOutput: options.enableExperimentalTestOutput,
                sanitizers: globalOptions.build.sanitizers
            )
            let tests = try testSuites
                .filteredTests(specifier: options.testCaseSpecifier)
                .skippedTests(specifier: options.skippedTests(fileSystem: swiftCommandState.fileSystem))

            return (TestRunner.xctestArguments(forTestSpecifiers: tests.map(\.specifier)), tests.count)
        }
    }

    /// Generate xUnit file if requested.
    private func generateXUnitOutputIfRequested(
        for testResults: [ParallelTestRunner.TestResult],
        swiftCommandState: SwiftCommandState
    ) throws {
        guard let xUnitOutput = options.xUnitOutput else {
            return
        }

        let generator = XUnitGenerator(
            fileSystem: swiftCommandState.fileSystem,
            results: testResults
        )
        try generator.generate(
            at: xUnitOutput,
            detailedFailureMessage: self.options.shouldShowDetailedFailureMessage
        )
    }

    // MARK: - Common implementation

    public func run(_ swiftCommandState: SwiftCommandState) async throws {
        do {
            // Validate commands arguments
            try self.validateArguments(swiftCommandState: swiftCommandState)
        } catch {
            swiftCommandState.observabilityScope.emit(error)
            throw ExitCode.failure
        }

        if self.options.shouldPrintCodeCovPath {
            try await printCodeCovPath(swiftCommandState)
        } else if self.options._deprecated_shouldListTests {
            // backward compatibility 6/2022 for deprecation of flag into a subcommand
            let command = try List.parse()
            try await command.run(swiftCommandState)
        } else {
            let (productsBuildParameters, _) = try swiftCommandState.buildParametersForTest(options: self.options)
            let testProducts = try await buildTestsIfNeeded(swiftCommandState: swiftCommandState)

            // Clean out the code coverage directory that may contain stale
            // profraw files from a previous run of the code coverage tool.
            if self.options.enableCodeCoverage {
                try swiftCommandState.fileSystem.removeFileTree(productsBuildParameters.codeCovPath)
            }

            try await run(swiftCommandState, buildParameters: productsBuildParameters, testProducts: testProducts)

            // Process code coverage if requested. We do not process it if the test run failed.
            // See https://github.com/swiftlang/swift-package-manager/pull/6894 for more info.
            if self.options.enableCodeCoverage, swiftCommandState.executionStatus != .failure {
                try await processCodeCoverage(testProducts, swiftCommandState: swiftCommandState)
            }
        }
    }

    private func runTestProducts(
        _ testProducts: [BuiltTestProduct],
        additionalArguments: [String],
        productsBuildParameters: BuildParameters,
        swiftCommandState: SwiftCommandState,
        library: TestingLibrary
    ) async throws -> TestRunner.Result {
        // Pass through all arguments from the command line to Swift Testing.
        var additionalArguments = additionalArguments
        if library == .swiftTesting {
            // Reconstruct the arguments list. If an xUnit path was specified, remove it.
            var commandLineArguments = [String]()
            var originalCommandLineArguments = CommandLine.arguments.dropFirst().makeIterator()
            while let arg = originalCommandLineArguments.next() {
                if arg == "--xunit-output" {
                    _ = originalCommandLineArguments.next()
                } else {
                    commandLineArguments.append(arg)
                }
            }
            additionalArguments += commandLineArguments

            if var xunitPath = options.xUnitOutput {
                if options.testLibraryOptions.isEnabled(.xctest, swiftCommandState: swiftCommandState) {
                    // We are running Swift Testing, XCTest is also running in this session, and an xUnit path
                    // was specified. Make sure we don't stomp on XCTest's XML output by having Swift Testing
                    // write to a different path.
                    var xunitFileName = "\(xunitPath.basenameWithoutExt)-swift-testing"
                    if let ext = xunitPath.extension {
                        xunitFileName = "\(xunitFileName).\(ext)"
                    }
                    xunitPath = xunitPath.parentDirectory.appending(xunitFileName)
                }
                additionalArguments += ["--xunit-output", xunitPath.pathString]
            }
        }

        let toolchain = try swiftCommandState.getTargetToolchain()
        let testEnv = try TestingSupport.constructTestEnvironment(
            toolchain: toolchain,
            destinationBuildParameters: productsBuildParameters,
            sanitizers: globalOptions.build.sanitizers,
            library: library
        )

        let runnerPaths: [AbsolutePath] = switch library {
        case .xctest:
            testProducts.map(\.bundlePath)
        case .swiftTesting:
            testProducts.map(\.binaryPath)
        }

        let runner = TestRunner(
            bundlePaths: runnerPaths,
            additionalArguments: additionalArguments,
            cancellator: swiftCommandState.cancellator,
            toolchain: toolchain,
            testEnv: testEnv,
            observabilityScope: swiftCommandState.observabilityScope,
            library: library
        )

        // Finally, run the tests.
        return runner.test(outputHandler: {
            // command's result output goes on stdout
            // ie "swift test" should output to stdout
            print($0, terminator: "")
        })
    }

    private static func handleTestOutput(productsBuildParameters: BuildParameters, packagePath: AbsolutePath) throws {
        guard localFileSystem.exists(productsBuildParameters.testOutputPath) else {
            print("No existing test output found.")
            return
        }

        let lines = try String(contentsOfFile: productsBuildParameters.testOutputPath.pathString).components(separatedBy: "\n")
        let events = try lines.map { try JSONDecoder().decode(TestEventRecord.self, from: $0) }

        let caseEvents = events.compactMap { $0.caseEvent }
        let failureRecords = events.compactMap { $0.caseFailure }
        let expectedFailures = failureRecords.filter({ $0.failureKind.isExpected == true })
        let unexpectedFailures = failureRecords.filter { $0.failureKind.isExpected == false }.sorted(by: { lhs, rhs in
            guard let lhsLocation = lhs.issue.sourceCodeContext.location, let rhsLocation = rhs.issue.sourceCodeContext.location else {
                return lhs.description < rhs.description
            }

            if lhsLocation.file == rhsLocation.file {
                return lhsLocation.line < rhsLocation.line
            } else {
                return lhsLocation.file < rhsLocation.file
            }
        }).map { $0.description(with: packagePath.pathString) }

        let startedTests = caseEvents.filter { $0.event == .start }.count
        let finishedTests = caseEvents.filter { $0.event == .finish }.count
        let totalFailures = expectedFailures.count + unexpectedFailures.count
        print("\nRan \(finishedTests)/\(startedTests) tests, \(totalFailures) failures (\(unexpectedFailures.count) unexpected):\n")
        print("\(unexpectedFailures.joined(separator: "\n"))")
    }

    /// Processes the code coverage data and emits a json.
    private func processCodeCoverage(
        _ testProducts: [BuiltTestProduct],
        swiftCommandState: SwiftCommandState
    ) async throws {
        let workspace = try swiftCommandState.getActiveWorkspace()
        let root = try swiftCommandState.getWorkspaceRoot()
        let rootManifests = try await workspace.loadRootManifests(
            packages: root.packages,
            observabilityScope: swiftCommandState.observabilityScope
        )
        guard let rootManifest = rootManifests.values.first else {
            throw StringError("invalid manifests at \(root.packages)")
        }

        // Merge all the profraw files to produce a single profdata file.
        try await mergeCodeCovRawDataFiles(swiftCommandState: swiftCommandState)

        let (productsBuildParameters, _) = try swiftCommandState.buildParametersForTest(options: self.options)
        for product in testProducts {
            // Export the codecov data as JSON.
            let jsonPath = productsBuildParameters.codeCovAsJSONPath(packageName: rootManifest.displayName)
            try await exportCodeCovAsJSON(to: jsonPath, testBinary: product.binaryPath, swiftCommandState: swiftCommandState)
        }
    }

    /// Merges all profraw profiles in codecoverage directory into default.profdata file.
    private func mergeCodeCovRawDataFiles(swiftCommandState: SwiftCommandState) async throws {
        // Get the llvm-prof tool.
        let llvmProf = try swiftCommandState.getTargetToolchain().getLLVMProf()

        // Get the profraw files.
        let (productsBuildParameters, _) = try swiftCommandState.buildParametersForTest(options: self.options)
        let codeCovFiles = try swiftCommandState.fileSystem.getDirectoryContents(productsBuildParameters.codeCovPath)

        // Construct arguments for invoking the llvm-prof tool.
        var args = [llvmProf.pathString, "merge", "-sparse"]
        for file in codeCovFiles {
            let filePath = productsBuildParameters.codeCovPath.appending(component: file)
            if filePath.extension == "profraw" {
                args.append(filePath.pathString)
            }
        }
        args += ["-o", productsBuildParameters.codeCovDataFile.pathString]

        try await AsyncProcess.checkNonZeroExit(arguments: args)
    }

    /// Exports profdata as a JSON file.
    private func exportCodeCovAsJSON(
        to path: AbsolutePath,
        testBinary: AbsolutePath,
        swiftCommandState: SwiftCommandState
    ) async throws {
        // Export using the llvm-cov tool.
        let llvmCov = try swiftCommandState.getTargetToolchain().getLLVMCov()
        let (productsBuildParameters, _) = try swiftCommandState.buildParametersForTest(options: self.options)
        let args = [
            llvmCov.pathString,
            "export",
            "-instr-profile=\(productsBuildParameters.codeCovDataFile)",
            testBinary.pathString
        ]
        let result = try await AsyncProcess.popen(arguments: args)

        if result.exitStatus != .terminated(code: 0) {
            let output = try result.utf8Output() + result.utf8stderrOutput()
            throw StringError("Unable to export code coverage:\n \(output)")
        }
        try swiftCommandState.fileSystem.writeFileContents(path, bytes: ByteString(result.output.get()))
    }

    /// Builds the "test" target if enabled in options.
    ///
    /// - Returns: The paths to the build test products.
    private func buildTestsIfNeeded(
        swiftCommandState: SwiftCommandState
    ) async throws -> [BuiltTestProduct] {
        let (productsBuildParameters, toolsBuildParameters) = try swiftCommandState.buildParametersForTest(options: self.options)
        return try await Commands.buildTestsIfNeeded(
            swiftCommandState: swiftCommandState,
            productsBuildParameters: productsBuildParameters,
            toolsBuildParameters: toolsBuildParameters,
            testProduct: self.options.sharedOptions.testProduct,
            traitConfiguration: .init(traitOptions: self.options.traits)
        )
    }

    /// Private function that validates the commands arguments
    ///
    /// - Throws: if a command argument is invalid
    private func validateArguments(swiftCommandState: SwiftCommandState) throws {
        // Validation for --num-workers.
        if let workers = options.numberOfWorkers {
            // The --num-worker option should be called with --parallel. Since
            // this option does not affect swift-testing at this time, we can
            // effectively ignore that it defaults to enabling parallelization.
            guard options.shouldRunInParallel else {
                throw StringError("--num-workers must be used with --parallel")
            }

            guard workers > 0 else {
                throw StringError("'--num-workers' must be greater than zero")
            }

            guard options.testLibraryOptions.isEnabled(.xctest, swiftCommandState: swiftCommandState) else {
                throw StringError("'--num-workers' is only supported when testing with XCTest")
            }
        }

        if options._deprecated_shouldListTests {
            swiftCommandState.observabilityScope.emit(warning: "'--list-tests' option is deprecated; use 'swift test list' instead")
        }
    }

    public init() {}
}

extension SwiftTestCommand {
    func printCodeCovPath(_ swiftCommandState: SwiftCommandState) async throws {
        let workspace = try swiftCommandState.getActiveWorkspace()
        let root = try swiftCommandState.getWorkspaceRoot()
        let rootManifests = try await workspace.loadRootManifests(
            packages: root.packages,
            observabilityScope: swiftCommandState.observabilityScope
        )
        guard let rootManifest = rootManifests.values.first else {
            throw StringError("invalid manifests at \(root.packages)")
        }
        let (productsBuildParameters, _) = try swiftCommandState.buildParametersForTest(enableCodeCoverage: true)
        print(productsBuildParameters.codeCovAsJSONPath(packageName: rootManifest.displayName))
    }
}

extension SwiftTestCommand {
    struct Last: SwiftCommand {
        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        func run(_ swiftCommandState: SwiftCommandState) throws {
            try SwiftTestCommand.handleTestOutput(
                productsBuildParameters: try swiftCommandState.productsBuildParameters,
                packagePath: localFileSystem.currentWorkingDirectory ?? .root // by definition runs in the current working directory
            )
        }
    }

    struct List: AsyncSwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Lists test methods in specifier format"
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @OptionGroup()
        var sharedOptions: SharedOptions

        /// Which testing libraries to use (and any related options.)
        @OptionGroup()
        var testLibraryOptions: TestLibraryOptions

        /// Options for Swift Testing's event stream.
        @OptionGroup()
        var testEventStreamOptions: TestEventStreamOptions

        @OptionGroup(visibility: .hidden)
        package var traits: TraitOptions

        // for deprecated passthrough from SwiftTestTool (parse will fail otherwise)
        @Flag(name: [.customLong("list-tests"), .customShort("l")], help: .hidden)
        var _deprecated_passthrough: Bool = false

        func run(_ swiftCommandState: SwiftCommandState) async throws {
            do {
                try await self.runCommand(swiftCommandState)
            } catch let error as FileSystemError {
                if sharedOptions.shouldSkipBuilding {
                    throw ErrorWithContext(error, """
                        Test build artifacts were not found in the build folder.
                        The `--skip-build` flag was provided; either build the tests first with \
                        `swift build --build tests` or rerun the `swift test list` command without \
                        `--skip-build`
                        """
                    )
                }
                throw error
            }
        }

        func runCommand(_ swiftCommandState: SwiftCommandState) async throws {
            let (productsBuildParameters, toolsBuildParameters) = try swiftCommandState.buildParametersForTest(
                enableCodeCoverage: false,
                shouldSkipBuilding: sharedOptions.shouldSkipBuilding
            )
            let testProducts = try await buildTestsIfNeeded(
                swiftCommandState: swiftCommandState,
                productsBuildParameters: productsBuildParameters,
                toolsBuildParameters: toolsBuildParameters
            )

            let toolchain = try swiftCommandState.getTargetToolchain()
            let testEnv = try TestingSupport.constructTestEnvironment(
                toolchain: toolchain,
                destinationBuildParameters: productsBuildParameters,
                sanitizers: globalOptions.build.sanitizers,
                library: .swiftTesting
            )

            if testLibraryOptions.isEnabled(.xctest, swiftCommandState: swiftCommandState) {
                let testSuites = try TestingSupport.getTestSuites(
                    in: testProducts,
                    swiftCommandState: swiftCommandState,
                    enableCodeCoverage: false,
                    shouldSkipBuilding: sharedOptions.shouldSkipBuilding,
                    experimentalTestOutput: false,
                    sanitizers: globalOptions.build.sanitizers
                )

                // Print the tests.
                for test in testSuites.allTests {
                    print(test.specifier)
                }
            }

            if testLibraryOptions.isEnabled(.swiftTesting, swiftCommandState: swiftCommandState) {
                lazy var testEntryPointPath = testProducts.lazy.compactMap(\.testEntryPointPath).first
                if testLibraryOptions.isExplicitlyEnabled(.swiftTesting, swiftCommandState: swiftCommandState) || testEntryPointPath == nil {
                    let additionalArguments = ["--list-tests"] + CommandLine.arguments.dropFirst()
                    let runner = TestRunner(
                        bundlePaths: testProducts.map(\.binaryPath),
                        additionalArguments: additionalArguments,
                        cancellator: swiftCommandState.cancellator,
                        toolchain: toolchain,
                        testEnv: testEnv,
                        observabilityScope: swiftCommandState.observabilityScope,
                        library: .swiftTesting
                    )

                    // Finally, run the tests.
                    let result = runner.test(outputHandler: {
                        // command's result output goes on stdout
                        // ie "swift test" should output to stdout
                        print($0, terminator: "")
                    })
                    if result == .failure {
                        swiftCommandState.executionStatus = .failure
                        // If the runner reports failure do a check to ensure
                        // all the binaries are present on the file system.
                        for path in testProducts.map(\.binaryPath) {
                            if !swiftCommandState.fileSystem.exists(path) {
                                throw FileSystemError(.noEntry, path)
                            }
                        }
                    }
                } else if let testEntryPointPath {
                    // Cannot run Swift Testing because an entry point file was used and the developer
                    // didn't explicitly enable Swift Testing.
                    swiftCommandState.observabilityScope.emit(
                        debug: "Skipping automatic Swift Testing invocation (list) because a test entry point path is present: \(testEntryPointPath)"
                    )
                }
            }
        }

        private func buildTestsIfNeeded(
            swiftCommandState: SwiftCommandState,
            productsBuildParameters: BuildParameters,
            toolsBuildParameters: BuildParameters
        ) async throws -> [BuiltTestProduct] {
            return try await Commands.buildTestsIfNeeded(
                swiftCommandState: swiftCommandState,
                productsBuildParameters: productsBuildParameters,
                toolsBuildParameters: toolsBuildParameters,
                testProduct: self.sharedOptions.testProduct,
                traitConfiguration: .init(traitOptions: self.traits)
            )
        }
    }
}

/// A structure representing an individual unit test.
struct UnitTest {
    /// The path to the test product containing the test.
    let productPath: AbsolutePath

    /// The name of the unit test.
    let name: String

    /// The name of the test case.
    let testCase: String

    /// The specifier argument which can be passed to XCTest.
    var specifier: String {
        return testCase + "/" + name
    }
}

/// A class to run tests on a XCTest binary.
///
/// Note: Executes the XCTest with inherited environment as it is convenient to pass sensitive
/// information like username, password etc to test cases via environment variables.
final class TestRunner {
    /// Path to valid XCTest binaries.
    private let bundlePaths: [AbsolutePath]

    /// Arguments to pass to the test runner process, if any.
    private let additionalArguments: [String]

    private let cancellator: Cancellator

    // The toolchain to use.
    private let toolchain: UserToolchain

    private let testEnv: Environment

    /// ObservabilityScope  to emit diagnostics.
    private let observabilityScope: ObservabilityScope

    /// Which testing library to use with this test run.
    private let library: TestingLibrary

    /// Get the arguments used on this platform to pass test specifiers to XCTest.
    static func xctestArguments<S>(forTestSpecifiers testSpecifiers: S) -> [String] where S: Collection, S.Element == String {
        let testSpecifier: String
        if testSpecifiers.isEmpty {
            testSpecifier = "''"
        } else {
            testSpecifier = testSpecifiers.joined(separator: ",")
        }

#if os(macOS)
        return ["-XCTest", testSpecifier]
#else
        return [testSpecifier]
#endif
    }

    /// Creates an instance of TestRunner.
    ///
    /// - Parameters:
    ///     - testPaths: Paths to valid XCTest binaries.
    ///     - additionalArguments: Arguments to pass to the test runner process.
    init(
        bundlePaths: [AbsolutePath],
        additionalArguments: [String],
        cancellator: Cancellator,
        toolchain: UserToolchain,
        testEnv: Environment,
        observabilityScope: ObservabilityScope,
        library: TestingLibrary
    ) {
        self.bundlePaths = bundlePaths
        self.additionalArguments = additionalArguments
        self.cancellator = cancellator
        self.toolchain = toolchain
        self.testEnv = testEnv
        self.observabilityScope = observabilityScope.makeChildScope(description: "Test Runner")
        self.library = library
    }

    /// The result of running the test(s).
    enum Result: Equatable {
        /// The test(s) ran successfully.
        case success

        /// The test(s) failed.
        case failure

        /// There were no matching tests to run.
        ///
        /// XCTest does not report this result. It is used by Swift Testing only.
        case noMatchingTests
    }

    /// Executes and returns execution status. Prints test output on standard streams if requested
    /// - Returns: Result of spawning and running the test process, and the output stream result
    func test(outputHandler: @escaping (String) -> Void) -> Result {
        var results = [Result]()
        for path in self.bundlePaths {
            let testSuccess = self.test(at: path, outputHandler: outputHandler)
            results.append(testSuccess)
        }
        return results.reduce()
    }

    /// Constructs arguments to execute XCTest.
    private func args(forTestAt testPath: AbsolutePath) throws -> [String] {
        var args: [String] = []

        if let runner = self.toolchain.swiftSDK.toolset.knownTools[.testRunner], let runnerPath = runner.path {
            args.append(runnerPath.pathString)
            args.append(contentsOf: runner.extraCLIOptions)
            args.append(testPath.relative(to: localFileSystem.currentWorkingDirectory!).pathString)
            args.append(contentsOf: self.additionalArguments)
        } else {
#if os(macOS)
            switch library {
            case .xctest:
                guard let xctestPath = self.toolchain.xctestPath else {
                    throw TestError.xcodeNotInstalled
                }
                args += [xctestPath.pathString]
            case .swiftTesting:
                let helper = try self.toolchain.getSwiftTestingHelper()
                args += [helper.pathString, "--test-bundle-path", testPath.pathString]
            }
            args += self.additionalArguments
            args += [testPath.pathString]
    #else
            args += [testPath.pathString]
            args += self.additionalArguments
    #endif
        }

        if library == .swiftTesting {
            // HACK: tell the test bundle/executable that we want to run Swift Testing, not XCTest.
            // XCTest doesn't understand this argument (yet), so don't pass it there.
            args += ["--testing-library", "swift-testing"]
        }

        return args
    }

    private func test(at path: AbsolutePath, outputHandler: @escaping (String) -> Void) -> Result {
        let testObservabilityScope = self.observabilityScope.makeChildScope(description: "running test at \(path)")

        do {
            let outputHandler = { (bytes: [UInt8]) in
                if let output = String(bytes: bytes, encoding: .utf8) {
                    outputHandler(output)
                }
            }
            let outputRedirection = AsyncProcess.OutputRedirection.stream(
                stdout: outputHandler,
                stderr: outputHandler
            )
            let process = AsyncProcess(arguments: try args(forTestAt: path), environment: self.testEnv, outputRedirection: outputRedirection)
            guard let terminationKey = self.cancellator.register(process) else {
                return .failure // terminating
            }
            defer { self.cancellator.deregister(terminationKey) }
            try process.launch()
            let result = try process.waitUntilExit()
            switch result.exitStatus {
            case .terminated(code: 0):
                return .success
            case .terminated(code: EXIT_NO_TESTS_FOUND) where library == .swiftTesting:
                return .noMatchingTests
            #if !os(Windows)
            case .signalled(let signal) where ![SIGINT, SIGKILL, SIGTERM].contains(signal):
                testObservabilityScope.emit(error: "Exited with unexpected signal code \(signal)")
                return .failure
            #endif
            default:
                return .failure
            }
        } catch {
            testObservabilityScope.emit(error)
            return .failure
        }
    }
}

extension Collection where Element == TestRunner.Result {
    /// Reduce all results in this collection into a single result.
    func reduce() -> Element {
        if contains(.failure) {
            return .failure
        } else if isEmpty || contains(.success) {
            return .success
        } else {
            return .noMatchingTests
        }
    }
}

/// A class to run tests in parallel.
final class ParallelTestRunner {
    /// An enum representing result of a unit test execution.
    struct TestResult {
        var unitTest: UnitTest
        var output: String
        var success: Bool
        var duration: DispatchTimeInterval
    }

    /// Path to XCTest binaries.
    private let bundlePaths: [AbsolutePath]

    /// The queue containing list of tests to run (producer).
    private let pendingTests = SynchronizedQueue<UnitTest?>()

    /// The queue containing tests which are finished running.
    private let finishedTests = SynchronizedQueue<TestResult?>()

    /// Instance of a terminal progress animation.
    private let progressAnimation: ProgressAnimationProtocol

    /// Number of tests that will be executed.
    private var numTests = 0

    /// Number of the current tests that has been executed.
    private var numCurrentTest = 0

    /// True if all tests executed successfully.
    private(set) var ranSuccessfully = true

    private let cancellator: Cancellator

    private let toolchain: UserToolchain

    private let buildOptions: BuildOptions
    private let productsBuildParameters: BuildParameters

    /// Number of tests to execute in parallel.
    private let numJobs: Int

    /// Whether to display output from successful tests.
    private let shouldOutputSuccess: Bool

    /// ObservabilityScope to emit diagnostics.
    private let observabilityScope: ObservabilityScope

    init(
        bundlePaths: [AbsolutePath],
        cancellator: Cancellator,
        toolchain: UserToolchain,
        numJobs: Int,
        buildOptions: BuildOptions,
        productsBuildParameters: BuildParameters,
        shouldOutputSuccess: Bool,
        observabilityScope: ObservabilityScope
    ) {
        self.bundlePaths = bundlePaths
        self.cancellator = cancellator
        self.toolchain = toolchain
        self.numJobs = numJobs
        self.shouldOutputSuccess = shouldOutputSuccess
        self.observabilityScope = observabilityScope.makeChildScope(description: "Parallel Test Runner")

        // command's result output goes on stdout
        // ie "swift test" should output to stdout
        if Environment.current["SWIFTPM_TEST_RUNNER_PROGRESS_BAR"] == "lit" {
            self.progressAnimation = ProgressAnimation.percent(
                stream: TSCBasic.stdoutStream,
                verbose: false,
                header: "Testing:",
                isColorized: productsBuildParameters.outputParameters.isColorized
            )
        } else {
            self.progressAnimation = ProgressAnimation.ninja(
                stream: TSCBasic.stdoutStream,
                verbose: false
            )
        }

        self.buildOptions = buildOptions
        self.productsBuildParameters = productsBuildParameters

        assert(numJobs > 0, "num jobs should be > 0")
    }

    /// Updates the progress bar status.
    private func updateProgress(for test: UnitTest) {
        numCurrentTest += 1
        progressAnimation.update(step: numCurrentTest, total: numTests, text: "Testing \(test.specifier)")
    }

    private func enqueueTests(_ tests: [UnitTest]) throws {
        // Enqueue all the tests.
        for test in tests {
            pendingTests.enqueue(test)
        }
        self.numTests = tests.count
        self.numCurrentTest = 0
        // Enqueue the sentinels, we stop a thread when it encounters a sentinel in the queue.
        for _ in 0..<numJobs {
            pendingTests.enqueue(nil)
        }
    }

    /// Executes the tests spawning parallel workers. Blocks calling thread until all workers are finished.
    func run(_ tests: [UnitTest]) throws -> [TestResult] {
        assert(!tests.isEmpty, "There should be at least one test to execute.")

        let testEnv = try TestingSupport.constructTestEnvironment(
            toolchain: self.toolchain,
            destinationBuildParameters: self.productsBuildParameters,
            sanitizers: self.buildOptions.sanitizers,
            library: .xctest // swift-testing does not use ParallelTestRunner
        )

        // Enqueue all the tests.
        try enqueueTests(tests)

        // Create the worker threads.
        let workers: [Thread] = (0..<numJobs).map({ _ in
            let thread = Thread {
                // Dequeue a specifier and run it till we encounter nil.
                while let test = self.pendingTests.dequeue() {
                    let additionalArguments = TestRunner.xctestArguments(forTestSpecifiers: CollectionOfOne(test.specifier))
                    let testRunner = TestRunner(
                        bundlePaths: [test.productPath],
                        additionalArguments: additionalArguments,
                        cancellator: self.cancellator,
                        toolchain: self.toolchain,
                        testEnv: testEnv,
                        observabilityScope: self.observabilityScope,
                        library: .xctest // swift-testing does not use ParallelTestRunner
                    )
                    var output = ""
                    let outputLock = NSLock()
                    let start = DispatchTime.now()
                    let result = testRunner.test(outputHandler: { _output in outputLock.withLock{ output += _output }})
                    let duration = start.distance(to: .now())
                    if result == .failure {
                        self.ranSuccessfully = false
                    }
                    self.finishedTests.enqueue(TestResult(
                        unitTest: test,
                        output: output,
                        success: result != .failure,
                        duration: duration
                    ))
                }
            }
            thread.start()
            return thread
        })

        // List of processed tests.
        let processedTests = ThreadSafeArrayStore<TestResult>()

        // Report (consume) the tests which have finished running.
        while let result = finishedTests.dequeue() {
            updateProgress(for: result.unitTest)

            // Store the result.
            processedTests.append(result)

            // We can't enqueue a sentinel into finished tests queue because we won't know
            // which test is last one so exit this when all the tests have finished running.
            if numCurrentTest == numTests {
                break
            }
        }

        // Wait till all threads finish execution.
        workers.forEach { $0.join() }

        // Report the completion.
        progressAnimation.complete(success: processedTests.get().contains(where: { !$0.success }))

        // Print test results.
        for test in processedTests.get() {
            if (!test.success || shouldOutputSuccess) && !productsBuildParameters.testingParameters.experimentalTestOutput {
                // command's result output goes on stdout
                // ie "swift test" should output to stdout
                print(test.output)
            }
        }

        return processedTests.get()
    }
}

/// A struct to hold the XCTestSuite data.
struct TestSuite {
    /// A struct to hold a XCTestCase data.
    struct TestCase {
        /// Name of the test case.
        let name: String

        /// Array of test methods in this test case.
        let tests: [String]
    }

    /// The name of the test suite.
    let name: String

    /// Array of test cases in this test suite.
    let tests: [TestCase]

    /// Parses a JSON String to array of TestSuite.
    ///
    /// - Parameters:
    ///     - jsonString: JSON string to be parsed.
    ///     - context: the commandline which produced the given JSON.
    ///
    /// - Throws: JSONDecodingError, TestError
    ///
    /// - Returns: Array of TestSuite.
    static func parse(jsonString: String, context: String) throws -> [TestSuite] {
        let json: JSON
        do {
            json = try JSON(string: jsonString)
        } catch {
            throw TestError.invalidListTestJSONData(context: context, underlyingError: error)
        }
        return try TestSuite.parse(json: json, context: context)
    }

    /// Parses the JSON object into array of TestSuite.
    ///
    /// - Parameters:
    ///     - json: An object of JSON.
    ///     - context: the commandline which produced the given JSON.
    ///
    /// - Throws: TestError
    ///
    /// - Returns: Array of TestSuite.
    static func parse(json: JSON, context: String) throws -> [TestSuite] {
        guard case let .dictionary(contents) = json,
              case let .array(testSuites)? = contents["tests"] else {
            throw TestError.invalidListTestJSONData(context: context)
        }

        return try testSuites.map({ testSuite in
            guard case let .dictionary(testSuiteData) = testSuite,
                  case let .string(name)? = testSuiteData["name"],
                  case let .array(allTestsData)? = testSuiteData["tests"] else {
                throw TestError.invalidListTestJSONData(context: context)
            }

            let testCases: [TestSuite.TestCase] = try allTestsData.map({ testCase in
                guard case let .dictionary(testCaseData) = testCase,
                      case let .string(name)? = testCaseData["name"],
                      case let .array(tests)? = testCaseData["tests"] else {
                    throw TestError.invalidListTestJSONData(context: context)
                }
                let testMethods: [String] = try tests.map({ test in
                    guard case let .dictionary(testData) = test,
                          case let .string(testMethod)? = testData["name"] else {
                        throw TestError.invalidListTestJSONData(context: context)
                    }
                    return testMethod
                })
                return TestSuite.TestCase(name: name, tests: testMethods)
            })

            return TestSuite(name: name, tests: testCases)
        })
    }
}

fileprivate extension Dictionary where Key == AbsolutePath, Value == [TestSuite] {
    /// Returns all the unit tests of the test suites.
    var allTests: [UnitTest] {
        var allTests: [UnitTest] = []
        for (bundlePath, testSuites) in self {
            for testSuite in testSuites {
                for testCase in testSuite.tests {
                    for test in testCase.tests {
                        allTests.append(UnitTest(productPath: bundlePath, name: test, testCase: testCase.name))
                    }
                }
            }
        }
        return allTests
    }

    /// Return tests matching the provided specifier
    func filteredTests(specifier: TestCaseSpecifier) throws -> [UnitTest] {
        switch specifier {
        case .none:
            return allTests
        case .regex(let patterns):
            return allTests.filter({ test in
                patterns.contains { pattern in
                    test.specifier.range(of: pattern,
                                         options: .regularExpression) != nil
                }
            })
        case .specific(let name):
            return allTests.filter{ $0.specifier == name }
        case .skip:
            throw InternalError("Tests to skip should never have been passed here.")
        }
    }
}

fileprivate extension Array where Element == UnitTest {
    /// Skip tests matching the provided specifier
    func skippedTests(specifier: TestCaseSpecifier) throws -> [UnitTest] {
        switch specifier {
        case .none:
            return self
        case .skip(let skippedTests):
            var result = self
            for skippedTest in skippedTests {
                result = result.filter{
                    $0.specifier.range(of: skippedTest, options: .regularExpression) == nil
                }
            }
            return result
        case .regex, .specific:
            throw InternalError("Tests to filter should never have been passed here.")
        }
    }
}

/// xUnit XML file generator for a swift-test run.
final class XUnitGenerator {
    typealias TestResult = ParallelTestRunner.TestResult

    /// The file system to use
    let fileSystem: FileSystem

    /// The test results.
    let results: [TestResult]

    init(fileSystem: FileSystem, results: [TestResult]) {
        self.fileSystem = fileSystem
        self.results = results
    }

    /// Generate the file at the given path.
    func generate(at path: AbsolutePath, detailedFailureMessage: Bool) throws {
        var content =
            """
            <?xml version="1.0" encoding="UTF-8"?>

            <testsuites>

            """

        // Get the failure count.
        let failures = results.filter({ !$0.success }).count
        let duration = results.compactMap({ $0.duration.timeInterval() }).reduce(0.0, +)

        // We need better output reporting from XCTest.
        content +=
            """
            <testsuite name="TestResults" errors="0" tests="\(results.count)" failures="\(failures)" time="\(duration)">

            """

        // Generate a testcase entry for each result.
        //
        // FIXME: This is very minimal right now. We should allow including test output etc.
        for result in results {
            let test = result.unitTest
            let duration = result.duration.timeInterval() ?? 0.0
            content +=
                """
                <testcase classname="\(test.testCase)" name="\(test.name)" time="\(duration)">

                """

            if !result.success {
                let failureMessage = detailedFailureMessage ? result.output.map(_escapeForXML).joined() : "failure"
                content += "<failure message=\"\(failureMessage)\"></failure>\n"
            }

            content += "</testcase>\n"
        }

        content +=
            """
            </testsuite>
            </testsuites>

            """

        try self.fileSystem.writeFileContents(path, string: content)
    }
}

/// Escape a single Unicode character for use in an XML-encoded string.
///
/// - Parameters:
///   - character: The character to escape.
///
/// - Returns: `character`, or a string containing its escaped form.
private func _escapeForXML(_ character: Character) -> String {
    switch character {
    case "\"":
        "&quot;"
    case "<":
        "&lt;"
    case ">":
        "&gt;"
    case "&":
        "&amp;"
    case _ where !character.isASCII || character.isNewline:
    character.unicodeScalars.lazy
        .map(\.value)
        .map { "&#\($0);" }
        .joined()
    default:
    String(character)
    }
}

extension SwiftCommandState {
    func buildParametersForTest(
        options: TestCommandOptions
    ) throws -> (productsBuildParameters: BuildParameters, toolsBuildParameters: BuildParameters) {
        try self.buildParametersForTest(
            enableCodeCoverage: options.enableCodeCoverage,
            enableTestability: options.enableTestableImports,
            shouldSkipBuilding: options.sharedOptions.shouldSkipBuilding,
            experimentalTestOutput: options.enableExperimentalTestOutput
        )
    }
}

extension TestCommandOptions {
    func skippedTests(fileSystem: FileSystem) -> TestCaseSpecifier {
        // TODO: Remove this once the environment variable is no longer used.
        if let override = skippedTestsOverride(fileSystem: fileSystem) {
            return override
        }

        return self._testCaseSkip.isEmpty
            ? .none
            : .skip(self._testCaseSkip)
    }

    /// Returns the test case specifier if overridden in the env.
    private func skippedTestsOverride(fileSystem: FileSystem) -> TestCaseSpecifier? {
        guard let override = Environment.current["_SWIFTPM_SKIP_TESTS_LIST"] else {
            return nil
        }

        do {
            let skipTests: [String.SubSequence]
            // Read from the file if it exists.
            if let path = try? AbsolutePath(validating: override), fileSystem.exists(path) {
                let contents: String = try fileSystem.readFileContents(path)
                skipTests = contents.split(separator: "\n", omittingEmptySubsequences: true)
            } else {
                // Otherwise, read the env variable.
                skipTests = override.split(separator: ":", omittingEmptySubsequences: true)
            }

            return .skip(skipTests.map(String.init))
        } catch {
            // FIXME: We should surface errors from here.
        }
        return nil
    }
}

extension BuildParameters {
    fileprivate func codeCovAsJSONPath(packageName: String) -> AbsolutePath {
        return self.codeCovPath.appending(component: packageName + ".json")
    }
}

private extension Basics.Diagnostic {
    static var noMatchingTests: Self {
        .warning("No matching test cases were run")
    }
}

/// The exit code returned to Swift Package Manager by Swift Testing when no
/// tests matched the inputs specified by the developer (or, for the case of
/// `swift test list`, when no tests were found.)
///
/// Because Swift Package Manager does not directly link to the testing library,
/// it duplicates the definition of this constant in its own source. Any changes
/// to this constant in either package must be mirrored in the other.
private var EXIT_NO_TESTS_FOUND: CInt {
#if os(macOS) || os(Linux) || canImport(Android) || os(FreeBSD)
    EX_UNAVAILABLE
#elseif os(Windows)
    ERROR_NOT_FOUND
#else
#warning("Platform-specific implementation missing: value for EXIT_NO_TESTS_FOUND unavailable")
    return 2 // We're assuming that EXIT_SUCCESS = 0 and EXIT_FAILURE = 1.
#endif
}

/// Builds the "test" target if enabled in options.
///
/// - Returns: The paths to the build test products.
private func buildTestsIfNeeded(
    swiftCommandState: SwiftCommandState,
    productsBuildParameters: BuildParameters,
    toolsBuildParameters: BuildParameters,
    testProduct: String?,
    traitConfiguration: TraitConfiguration
) async throws -> [BuiltTestProduct] {
    let buildSystem = try await swiftCommandState.createBuildSystem(
        traitConfiguration: traitConfiguration,
        productsBuildParameters: productsBuildParameters,
        toolsBuildParameters: toolsBuildParameters
    )

    let subset: BuildSubset = if let testProduct {
        .product(testProduct)
    } else {
        .allIncludingTests
    }

    try await buildSystem.build(subset: subset)

    // Find the test product.
    let testProducts = await buildSystem.builtTestProducts
    guard !testProducts.isEmpty else {
        if let testProduct {
            throw TestError.productIsNotTest(productName: testProduct)
        } else {
            throw TestError.testsNotFound
        }
    }

    if let testProductName = testProduct {
        guard let selectedTestProduct = testProducts.first(where: { $0.productName == testProductName }) else {
            throw TestError.testProductNotFound(productName: testProductName)
        }

        return [selectedTestProduct]
    } else {
        return testProducts
    }
}
