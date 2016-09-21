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

import func POSIX.chdir
import func POSIX.exit

private enum TestError: Swift.Error {
    case invalidListTestJSONData
    case multipleTestProducts
    case testsExecutableNotFound
}

extension TestError: CustomStringConvertible {
    var description: String {
        switch self {
        case .testsExecutableNotFound:
            return "no tests found to execute, create a module in your `Tests' directory"
        case .invalidListTestJSONData:
            return "Invalid list test JSON structure."
        case .multipleTestProducts:
            return "cannot test packages with multiple test products defined"
        }
    }
}

public enum TestMode: Argument, Equatable, CustomStringConvertible {
    case usage
    case version
    case listTests
    case run(String?)
    case runInParallel

    public init?(argument: String, pop: @escaping () -> String?) throws {
        switch argument {
        case "--help", "-h":
            self = .usage
        case "-l", "--list-tests":
            self = .listTests
        case "-s", "--specifier":
            guard let specifier = pop() else { throw OptionParserError.expectedAssociatedValue(argument) }
            self = .run(specifier)
        case "--version":
            self = .version
        case "--parallel":
            self = .runInParallel
        default:
            return nil
        }
    }

    public var description: String {
        switch self {
        case .usage:
            return "--help"
        case .listTests:
            return "--list-tests"
        case .run(let specifier):
            return specifier ?? ""
        case .version: return "--version"
        case .runInParallel:
            return "--parallel"
        }
    }
}

public func ==(lhs: TestMode, rhs: TestMode) -> Bool {
    return lhs.description == rhs.description
}

// FIXME: Merge this with the `swift-build` arguments.
private enum TestToolFlag: Argument {
    case xcc(String)
    case xld(String)
    case xswiftc(String)
    case chdir(AbsolutePath)
    case buildPath(AbsolutePath)
    case enableNewResolver
    case colorMode(ColorWrap.Mode)
    case skipBuild
    case verbose(Int)

    init?(argument: String, pop: @escaping () -> String?) throws {
        func forcePop() throws -> String {
            guard let value = pop() else { throw OptionParserError.expectedAssociatedValue(argument) }
            return value
        }
        
        switch argument {
        case Flag.chdir, Flag.C:
            self = try .chdir(AbsolutePath(forcePop(), relativeTo: currentWorkingDirectory))
        case "--verbose", "-v":
            self = .verbose(1)
        case "--skip-build":
            self = .skipBuild
        case "-Xcc":
            self = try .xcc(forcePop())
        case "-Xlinker":
            self = try .xld(forcePop())
        case "-Xswiftc":
            self = try .xswiftc(forcePop())
        case "--build-path":
            self = try .buildPath(AbsolutePath(forcePop(), relativeTo: currentWorkingDirectory))
        case "--enable-new-resolver":
            self = .enableNewResolver
        case "--color":
            let rawValue = try forcePop()
            guard let mode = ColorWrap.Mode(rawValue) else  {
                throw OptionParserError.invalidUsage("invalid color mode: \(rawValue)")
            }
            self = .colorMode(mode)
        default:
            return nil
        }
    }
}

public class TestToolOptions: Options {
    var buildTests: Bool = true
    var flags = BuildFlags()
}

/// swift-test tool namespace
public class SwiftTestTool: SwiftTool<TestMode, TestToolOptions> {

    override func runImpl() throws {

        switch mode {
        case .usage:
            SwiftTestTool.usage()

        case .version:
            print(Versioning.currentVersion.completeDisplayString)

        case .listTests:
            let testPath = try buildTestsIfNeeded(options)
            let testSuites = try SwiftTestTool.getTestSuites(path: testPath)
            // Print the tests.
            for testSuite in testSuites {
                for testCase in testSuite.tests {
                    for test in testCase.tests {
                        print(testCase.name + "/" + test)
                    }
                }
            }

        case .run(let specifier):
            let testPath = try buildTestsIfNeeded(options)
            let success: Bool = TestRunner(path: testPath, xctestArg: specifier).test()
            exit(success ? 0 : 1)

        case .runInParallel:
            let testPath = try buildTestsIfNeeded(options)
            let runner = ParallelTestRunner(testPath: testPath)
            try runner.run()
            exit(runner.success ? 0 : 1)
        }
    }

    /// Builds the "test" target if enabled in options.
    ///
    /// - Returns: The path to the test binary.
    private func buildTestsIfNeeded(_ options: TestToolOptions) throws -> AbsolutePath {
        let graph = try loadPackage()
        if options.buildTests {
            let yaml = try describe(buildPath, configuration, graph, flags: options.flags, toolchain: UserToolchain())
            try build(yamlPath: yaml, target: "test")
        }
                
        // See the logic in `PackageLoading`'s `PackageExtensions.swift`.
        //
        // FIXME: We should also check if the package has any test
        // modules, which isn't trivial (yet).
        let testProducts = graph.products.filter{
            if case .Test = $0.type {
                return true
            } else {
                return false
            }
        }
        if testProducts.count == 0 {
            throw TestError.testsExecutableNotFound
        } else if testProducts.count > 1 {
            throw TestError.multipleTestProducts
        } else {
            return buildPath.appending(RelativePath(configuration.dirname)).appending(component: testProducts[0].name + ".xctest")
        }
    }

    // FIXME: We need to support testing in other build configurations, but need
    // to solve the testability problem first.
    private let configuration = Build.Configuration.debug

    override class func usage(_ print: (String) -> Void = { print($0) }) {
        //     .........10.........20.........30.........40.........50.........60.........70..
        print("OVERVIEW: Build and run tests")
        print("")
        print("USAGE: swift test [options]")
        print("")
        print("OPTIONS:")
        print("  -s, --specifier <test-module>.<test-case>         Run a test case subclass")
        print("  -s, --specifier <test-module>.<test-case>/<test>  Run a specific test method")
        print("  -l, --list-tests                                  Lists test methods in specifier format")
        print("  -C, --chdir <path>     Change working directory before any other operation")
        print("  --build-path <path>    Specify build/cache directory [default: ./.build]")
        print("  --color <mode>         Specify color mode (auto|always|never) [default: auto]")
        print("  -v, --verbose          Increase verbosity of informational output")
        print("  --skip-build           Skip building the test target")
        print("  -Xcc <flag>              Pass flag through to all C compiler invocations")
        print("  -Xlinker <flag>          Pass flag through to all linker invocations")
        print("  -Xswiftc <flag>          Pass flag through to all Swift compiler invocations")
        print("")
        print("NOTE: Use `swift package` to perform other functions on packages")
    }

    override class func parse(commandLineArguments args: [String]) throws -> (TestMode, TestToolOptions) {
        let (mode, flags): (TestMode?, [TestToolFlag]) = try Basic.parseOptions(arguments: args)

        let options = TestToolOptions()
        for flag in flags {
            switch flag {
            case .chdir(let path):
                options.chdir = path
            case .verbose(let amount):
                options.verbosity += amount
            case .xcc(let value):
                options.flags.cCompilerFlags.append(value)
            case .xld(let value):
                options.flags.linkerFlags.append(value)
            case .xswiftc(let value):
                options.flags.swiftCompilerFlags.append(value)
            case .buildPath(let path):
                options.buildPath = path
            case .enableNewResolver:
                options.enableNewResolver = true
            case .colorMode(let mode):
                options.colorMode = mode
            case .skipBuild:
                options.buildTests = false
            }
        }

        return (mode ?? .run(nil), options)
    }

    /// Locates XCTestHelper tool inside the libexec directory and bin directory.
    /// Note: It is a fatalError if we are not able to locate the tool.
    ///
    /// - Returns: Path to XCTestHelper tool.
    private static func xctestHelperPath() -> AbsolutePath {
        let xctestHelperBin = "swiftpm-xctest-helper"
        let binDirectory = AbsolutePath(CommandLine.arguments.first!, relativeTo: currentWorkingDirectory).parentDirectory
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
    fileprivate static func getTestSuites(path: AbsolutePath) throws -> [TestSuite] {
        // Run the correct tool.
      #if os(macOS)
        let tempFile = try TemporaryFile()
        let args = [SwiftTestTool.xctestHelperPath().asString, path.asString, tempFile.path.asString]
        try system(args, environment: ["DYLD_FRAMEWORK_PATH": try platformFrameworksPath().asString])
        // Read the temporary file's content.
        let data = try fopen(tempFile.path).readFileContents()
      #else
        let args = [path.asString, "--dump-tests-json"]
        let data = try popen(args)
      #endif
        // Parse json and return TestSuites.
        return try TestSuite.parse(jsonString: data)
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

    /// Creates an instance of TestRunner.
    ///
    /// - Parameters:
    ///     - path: Path to valid XCTest binary.
    ///     - xctestArg: Arguments to pass to XCTest.
    init(path: AbsolutePath, xctestArg: String? = nil) {
        self.path = path
        self.xctestArg = xctestArg
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

    /// Current inherited enviornment variables.
    private var environment: [String: String] {
        return ProcessInfo.processInfo.environment
    }

    /// Executes the tests without printing anything on standard streams.
    ///
    /// - Returns: A tuple with first bool member indicating if test execution returned code 0
    ///            and second argument containing the output of the execution.
    func test() -> (Bool, String) {
        var output = ""
        var success = true
        do {
            try popen(args(), redirectStandardError: true, environment: environment) { line in
                output += line
            }
        } catch {
            success = false
        }
        return (success, output)
    }

    /// Executes and returns execution status. Prints test output on standard streams.
    func test() -> Bool {
        let result: Void? = try? system(args(), environment: environment)
        return result != nil
    }
}

/// A class to run tests in parallel.
final class ParallelTestRunner {
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
    private(set) var success: Bool = true

    init(testPath: AbsolutePath) {
        self.testPath = testPath
        progressBar = createProgressBar(forStream: stdoutStream, header: "Tests")
    }

    /// Updates the progress bar status.
    private func updateProgress(for test: UnitTest) {
        numCurrentTest += 1
        progressBar.update(percent: 100*numCurrentTest/numTests, text: test.specifier)
    }

    func enqueueTests() throws {
        // Find all the test suites present in the test binary.
        let testSuites = try SwiftTestTool.getTestSuites(path: testPath)
        // FIXME: Add a count property in SynchronizedQueue.
        var numTests = 0
        // Enqueue all the tests.
        for testSuite in testSuites {
            for testCase in testSuite.tests {
                for test in testCase.tests {
                    numTests += 1
                    pendingTests.enqueue(UnitTest(name: test, testCase: testCase.name))
                }
            }
        }
        self.numTests = numTests
        self.numCurrentTest = 0
        // Enqueue the sentinels, we stop a thread when it encounters a sentinel in the queue.
        for _ in 0..<numJobs {
            pendingTests.enqueue(nil)
        }
    }

    /// Executes the tests spawning parallel workers. Blocks calling thread until all workers are finished.
    func run() throws {
        // Enqueue all the tests.
        try enqueueTests()

        // Create the worker threads.
        let workers: [Thread] = (0..<numJobs).map { _ in
            let thread = Thread {
                // Dequeue a specifier and run it till we encounter nil.
                while let test = self.pendingTests.dequeue() {
                    let testRunner = TestRunner(path: self.testPath, xctestArg: test.specifier)
                    let (success, output) = testRunner.test()
                    if success {
                        self.finishedTests.enqueue(.success(test))
                    } else {
                        self.success = false
                        self.finishedTests.enqueue(.failure(test, output: output))
                    }
                }
            }
            thread.start()
            return thread
        }

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

        return try testSuites.map { testSuite in
            guard case let .dictionary(testSuiteData) = testSuite,
                  case let .string(name)? = testSuiteData["name"],
                  case let .array(allTestsData)? = testSuiteData["tests"] else {
                throw TestError.invalidListTestJSONData
            }

            let testCases: [TestSuite.TestCase] = try allTestsData.map { testCase in
                guard case let .dictionary(testCaseData) = testCase,
                      case let .string(name)? = testCaseData["name"],
                      case let .array(tests)? = testCaseData["tests"] else {
                    throw TestError.invalidListTestJSONData
                }
                let testMethods: [String] = try tests.map { test in
                    guard case let .dictionary(testData) = test,
                          case let .string(testMethod)? = testData["name"] else {
                        throw TestError.invalidListTestJSONData
                    }
                    return testMethod
                }
                return TestSuite.TestCase(name: name, tests: testMethods)
            }
            return TestSuite(name: name, tests: testCases)
        }
    }
}
