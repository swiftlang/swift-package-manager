/*
This source file is part of the Swift.org open source project

Copyright 2015 - 2016 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import class Foundation.ProcessInfo

import Basic
import Build
import Utility

import func POSIX.exit


/// Diagnostics info for deprecated `--specifier` option
struct SpecifierDeprecatedDiagnostic: DiagnosticData {
    static let id = DiagnosticID(
        type: AnyDiagnostic.self,
        name: "org.swift.diags.specifier-deprecated",
        defaultBehavior: .warning,
        description: {
            $0 <<< "'--specifier' option is deprecated, use '--filter' instead."
        }
    )
}

private enum TestError: Swift.Error {
    case invalidListTestJSONData
    case multipleTestProducts
    case testsExecutableNotFound
}

extension TestError: CustomStringConvertible {
    var description: String {
        switch self {
        case .testsExecutableNotFound:
            return "no tests found to execute, create a target in your `Tests' directory"
        case .invalidListTestJSONData:
            return "Invalid list test JSON structure."
        case .multipleTestProducts:
            return "cannot test packages with multiple test products defined"
        }
    }
}

public class TestToolOptions: ToolOptions {
    /// Returns the mode in with the tool command should run.
    var mode: TestMode {
        // If we got version option, just print the version and exit.
        if shouldPrintVersion {
            return .version
        }

        if shouldRunInParallel {
            return .runParallel
        }

        if shouldListTests {
            return .listTests
        }

        return .runSerial
    }

    /// If the test target should be built before testing.
    var shouldBuildTests = true

    /// Build configuration.
    var config: Build.Configuration = .debug

    /// If tests should run in parallel mode.
    var shouldRunInParallel = false

    /// List the tests and exit.
    var shouldListTests = false

    var testCaseSpecifier: TestCaseSpecifier = .none
}

/// Tests filtering specifier
///
/// This is used to filter tests to run
///   .none     => No filtering
///   .specific => Specify test with fully quantified name
///   .regex    => RegEx pattern
public enum TestCaseSpecifier {
    case none
    case specific(String)
    case regex(String)
}

public enum TestMode {
    case version
    case listTests
    case runSerial
    case runParallel
}

/// swift-test tool namespace
public class SwiftTestTool: SwiftTool<TestToolOptions> {

   public convenience init(args: [String]) {
       self.init(
            toolName: "test",
            usage: "[options]",
            overview: "Build and run tests",
            args: args
        )
    }

    override func runImpl() throws {
        switch options.mode {
        case .version:
            print(Versioning.currentVersion.completeDisplayString)

        case .listTests:
            let testPath = try buildTestsIfNeeded(options)
            let testSuites = try getTestSuites(path: testPath)
            let tests = testSuites.filteredTests(specifier: options.testCaseSpecifier)

            // Print the tests.
            for test in tests {
                print(test.specifier)
            }

        case .runSerial:
            let testPath = try buildTestsIfNeeded(options)
            let testSuites = try getTestSuites(path: testPath)
            var ranSuccessfully = true

            if case .none = options.testCaseSpecifier {
                let runner = TestRunner(path: testPath,
                                        xctestArg: nil,
                                        processSet: processSet)
                ranSuccessfully = runner.test()
            } else {
                if case .specific = options.testCaseSpecifier {
                    diagnostics.emit(data: SpecifierDeprecatedDiagnostic())
                }
                let tests = testSuites.filteredTests(specifier: options.testCaseSpecifier)
                for test in tests {
                    let runner = TestRunner(path: testPath,
                                            xctestArg: test.specifier,
                                            processSet: processSet)
                    ranSuccessfully = ranSuccessfully && runner.test()
                }
            }

            exit(ranSuccessfully ? 0 : 1)

        case .runParallel:
            let testPath = try buildTestsIfNeeded(options)
            let testSuites = try getTestSuites(path: testPath)
            let tests = testSuites.filteredTests(specifier: options.testCaseSpecifier)
            let runner = ParallelTestRunner(testPath: testPath, processSet: processSet)
            try runner.run(tests)
            exit(runner.ranSuccesfully ? 0 : 1)
        }
    }

    /// Builds the "test" target if enabled in options.
    ///
    /// - Returns: The path to the test binary.
    private func buildTestsIfNeeded(_ options: TestToolOptions) throws -> AbsolutePath {
        let graph = try loadPackageGraph()
        if options.shouldBuildTests {
            try build(graph: graph, includingTests: true, config: options.config)
        }

        // See the logic in `PackageLoading`'s `PackageExtensions.swift`.
        //
        // FIXME: We should also check if the package has any test
        // targets, which isn't trivial (yet).
        let testProducts = graph.products.filter({
            if case .test = $0.type {
                return true
            } else {
                return false
            }
        })
        if testProducts.count == 0 {
            throw TestError.testsExecutableNotFound
        } else if testProducts.count > 1 {
            throw TestError.multipleTestProducts
        } else {
            return buildPath
                .appending(RelativePath(options.config.dirname))
                .appending(component: testProducts[0].name + ".xctest")
        }
    }

    override class func defineArguments(parser: ArgumentParser, binder: ArgumentBinder<TestToolOptions>) {

        binder.bind(
            option: parser.add(option: "--configuration", shortName: "-c", kind: Build.Configuration.self,
                usage: "Build with configuration (debug|release) [default: debug]"),
            to: { $0.config = $1 })

        binder.bind(
            option: parser.add(option: "--skip-build", kind: Bool.self,
                usage: "Skip building the test target"),
            to: { $0.shouldBuildTests = !$1 })

        binder.bind(
            option: parser.add(option: "--list-tests", shortName: "-l", kind: Bool.self,
                usage: "Lists test methods in specifier format"),
            to: { $0.shouldListTests = $1 })

        binder.bind(
            option: parser.add(option: "--parallel", kind: Bool.self,
                usage: "Run the tests in parallel."),
            to: { $0.shouldRunInParallel = $1 })

        binder.bind(
            option: parser.add(option: "--specifier", shortName: "-s", kind: String.self),
            to: { $0.testCaseSpecifier = .specific($1) })

        binder.bind(
            option: parser.add(option: "--filter", kind: String.self,
                usage: "Run test cases matching regular expression, Format: <test-target>.<test-case> or " +
                    "<test-target>.<test-case>/<test>"),
            to: { $0.testCaseSpecifier = .regex($1) })
    }

    /// Locates XCTestHelper tool inside the libexec directory and bin directory.
    /// Note: It is a fatalError if we are not able to locate the tool.
    ///
    /// - Returns: Path to XCTestHelper tool.
    private static func xctestHelperPath() -> AbsolutePath {
        let xctestHelperBin = "swiftpm-xctest-helper"
        let binDirectory = AbsolutePath(CommandLine.arguments.first!,
            relativeTo: currentWorkingDirectory).parentDirectory
        // XCTestHelper tool is installed in libexec.
        let maybePath = binDirectory.parentDirectory.appending(components: "libexec", "swift", "pm", xctestHelperBin)
        if isFile(maybePath) {
            return maybePath
        }
        // This will be true during swiftpm development.
        // FIXME: Factor all of the development-time resource location stuff into a common place.
        let path = binDirectory.appending(component: xctestHelperBin)
        if isFile(path) {
            return path
        }
        fatalError("XCTestHelper binary not found.")
    }

    /// Runs the corresponding tool to get tests JSON and create TestSuite array.
    /// On OSX, we use the swiftpm-xctest-helper tool bundled with swiftpm.
    /// On Linux, XCTest can dump the json using `--dump-tests-json` mode.
    ///
    /// - Parameters:
    ///     - path: Path to the XCTest bundle(OSX) or executable(Linux).
    ///
    /// - Throws: TestError, SystemError, Utility.Errror
    ///
    /// - Returns: Array of TestSuite
    fileprivate func getTestSuites(path: AbsolutePath) throws -> [TestSuite] {
        // Run the correct tool.
      #if os(macOS)
        let tempFile = try TemporaryFile()
        let args = [SwiftTestTool.xctestHelperPath().asString, path.asString, tempFile.path.asString]
        var env = ProcessInfo.processInfo.environment
        // Add the sdk platform path if we have it. If this is not present, we
        // might always end up failing.
        if let sdkPlatformFrameworksPath = Destination.sdkPlatformFrameworkPath() {
            env["DYLD_FRAMEWORK_PATH"] = sdkPlatformFrameworksPath.asString
        }
        try Process.checkNonZeroExit(arguments: args, environment: env)
        // Read the temporary file's content.
        let data = try fopen(tempFile.path).readFileContents()
      #else
        let args = [path.asString, "--dump-tests-json"]
        let data = try Process.checkNonZeroExit(arguments: args)
      #endif
        // Parse json and return TestSuites.
        return try TestSuite.parse(jsonString: data)
    }
}

/// A structure representing an individual unit test.
struct UnitTest {
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
/// Note: Executes the XCTest with inherited environment as it is convenient to pass senstive
/// information like username, password etc to test cases via enviornment variables.
final class TestRunner {
    /// Path to valid XCTest binary.
    private let path: AbsolutePath

    /// Arguments to pass to XCTest if any.
    private let xctestArg: String?

    private let processSet: ProcessSet

    /// Creates an instance of TestRunner.
    ///
    /// - Parameters:
    ///     - path: Path to valid XCTest binary.
    ///     - xctestArg: Arguments to pass to XCTest.
    init(path: AbsolutePath, xctestArg: String? = nil, processSet: ProcessSet) {
        self.path = path
        self.xctestArg = xctestArg
        self.processSet = processSet
    }

    /// Constructs arguments to execute XCTest.
    private func args() -> [String] {
        var args: [String] = []
      #if os(macOS)
        args = ["xcrun", "xctest"]
        if let xctestArg = xctestArg {
            args += ["-XCTest", xctestArg]
        }
        args += [path.asString]
      #else
        args += [path.asString]
        if let xctestArg = xctestArg {
            args += [xctestArg]
        }
      #endif
        return args
    }

    /// Executes the tests without printing anything on standard streams.
    ///
    /// - Returns: A tuple with first bool member indicating if test execution returned code 0
    ///            and second argument containing the output of the execution.
    func test() -> (Bool, String) {
        var output = ""
        var success = true
        do {
            let process = Process(arguments: args(), redirectOutput: true, verbose: false)
            try process.launch()
            let result = try process.waitUntilExit()
            output = try (result.utf8Output() + result.utf8stderrOutput()).chuzzle() ?? ""
            success = result.exitStatus == .terminated(code: 0)
        } catch {
            success = false
        }
        return (success, output)
    }

    /// Executes and returns execution status. Prints test output on standard streams.
    func test() -> Bool {
        do {
            let process = Process(arguments: args(), redirectOutput: false)
            try processSet.add(process)
            try process.launch()
            let result = try process.waitUntilExit()
            return result.exitStatus == .terminated(code: 0)
        } catch {
            return false
        }
    }
}

/// A class to run tests in parallel.
final class ParallelTestRunner {
    /// An enum representing result of a unit test execution.
    enum TestResult {
        case success(UnitTest)
        case failure(UnitTest, output: String)
    }

    /// Path to XCTest binary.
    private let testPath: AbsolutePath

    /// The queue containing list of tests to run (producer).
    private let pendingTests = SynchronizedQueue<UnitTest?>()

    /// The queue containing tests which are finished running.
    private let finishedTests = SynchronizedQueue<TestResult?>()

    /// Number of parallel workers to spawn.
    private var numJobs: Int {
        return ProcessInfo.processInfo.activeProcessorCount
    }

    /// Instance of progress bar. Animating progress bar if stream is a terminal otherwise
    /// a simple progress bar.
    private let progressBar: ProgressBarProtocol

    /// Number of tests that will be executed.
    private var numTests = 0

    /// Number of the current tests that has been executed.
    private var numCurrentTest = 0

    /// True if all tests executed successfully.
    private(set) var ranSuccesfully: Bool = true

    let processSet: ProcessSet

    init(testPath: AbsolutePath, processSet: ProcessSet) {
        self.testPath = testPath
        self.processSet = processSet
        progressBar = createProgressBar(forStream: stdoutStream, header: "Tests")
    }

    /// Updates the progress bar status.
    private func updateProgress(for test: UnitTest) {
        numCurrentTest += 1
        progressBar.update(percent: 100*numCurrentTest/numTests, text: test.specifier)
    }

    func enqueueTests(_ tests: [UnitTest]) throws {
        // FIXME: Add a count property in SynchronizedQueue.
        var numTests = 0
        // Enqueue all the tests.
        for test in tests {
            numTests += 1
            pendingTests.enqueue(test)
        }
        self.numTests = numTests
        self.numCurrentTest = 0
        // Enqueue the sentinels, we stop a thread when it encounters a sentinel in the queue.
        for _ in 0..<numJobs {
            pendingTests.enqueue(nil)
        }
    }

    /// Executes the tests spawning parallel workers. Blocks calling thread until all workers are finished.
    func run(_ tests: [UnitTest]) throws {
        // Enqueue all the tests.
        try enqueueTests(tests)

        // Create the worker threads.
        let workers: [Thread] = (0..<numJobs).map({ _ in
            let thread = Thread {
                // Dequeue a specifier and run it till we encounter nil.
                while let test = self.pendingTests.dequeue() {
                    let testRunner = TestRunner(
                        path: self.testPath, xctestArg: test.specifier, processSet: self.processSet)
                    let (success, output) = testRunner.test()
                    if success {
                        self.finishedTests.enqueue(.success(test))
                    } else {
                        self.ranSuccesfully = false
                        self.finishedTests.enqueue(.failure(test, output: output))
                    }
                }
            }
            thread.start()
            return thread
        })

        // Holds the output of test cases which failed.
        var failureOutput = [String]()
        // Report (consume) the tests which have finished running.
        while let result = finishedTests.dequeue() {
            switch result {
            case .success(let test):
                updateProgress(for: test)
            case .failure(let test, let output):
                updateProgress(for: test)
                failureOutput.append(output)
            }
            // We can't enqueue a sentinel into finished tests queue because we won't know
            // which test is last one so exit this when all the tests have finished running.
            if numCurrentTest == numTests { break }
        }

        // Wait till all threads finish execution.
        workers.forEach { $0.join() }
        progressBar.complete()
        printFailures(failureOutput)
    }

    /// Prints the output of the tests that failed.
    private func printFailures(_ failureOutput: [String]) {
        stdoutStream <<< "\n"
        for error in failureOutput {
            stdoutStream <<< error
        }
        stdoutStream.flush()
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
    ///
    /// - Throws: JSONDecodingError, TestError
    ///
    /// - Returns: Array of TestSuite.
    static func parse(jsonString: String) throws -> [TestSuite] {
        let json = try JSON(string: jsonString)
        return try TestSuite.parse(json: json)
    }

    /// Parses the JSON object into array of TestSuite.
    ///
    /// - Parameters:
    ///     - json: An object of JSON.
    ///
    /// - Throws: TestError
    ///
    /// - Returns: Array of TestSuite.
    static func parse(json: JSON) throws -> [TestSuite] {
        guard case let .dictionary(contents) = json,
              case let .array(testSuites)? = contents["tests"] else {
            throw TestError.invalidListTestJSONData
        }

        return try testSuites.map({ testSuite in
            guard case let .dictionary(testSuiteData) = testSuite,
                  case let .string(name)? = testSuiteData["name"],
                  case let .array(allTestsData)? = testSuiteData["tests"] else {
                throw TestError.invalidListTestJSONData
            }

            let testCases: [TestSuite.TestCase] = try allTestsData.map({ testCase in
                guard case let .dictionary(testCaseData) = testCase,
                      case let .string(name)? = testCaseData["name"],
                      case let .array(tests)? = testCaseData["tests"] else {
                    throw TestError.invalidListTestJSONData
                }
                let testMethods: [String] = try tests.map({ test in
                    guard case let .dictionary(testData) = test,
                          case let .string(testMethod)? = testData["name"] else {
                        throw TestError.invalidListTestJSONData
                    }
                    return testMethod
                })
                return TestSuite.TestCase(name: name, tests: testMethods)
            })
            
            return TestSuite(name: name, tests: testCases)
        })
    }
}


fileprivate extension Sequence where Iterator.Element == TestSuite {
    /// Returns all the unit tests of the test suites.
    var allTests: [UnitTest] {
        return flatMap { $0.tests }.flatMap({ testCase in
            testCase.tests.map{ UnitTest(name: $0, testCase: testCase.name) }
        })
    }

    /// Return tests matching the provided specifier
    func filteredTests(specifier: TestCaseSpecifier) -> [UnitTest] {
        switch specifier {
        case .none:
            return allTests
        case .regex(let pattern):
            return allTests.filter({ test in
                test.specifier.range(of: pattern,
                                     options: .regularExpression) != nil
            })
        case .specific(let name):
            return allTests.filter{ $0.specifier == name }
        }
    }
}
