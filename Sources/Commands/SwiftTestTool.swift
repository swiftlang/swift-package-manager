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

private enum Mode: Argument, Equatable, CustomStringConvertible {
    case usage
    case version
    case listTests
    case run(String?)

    init?(argument: String, pop: @escaping () -> String?) throws {
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
        default:
            return nil
        }
    }

    var description: String {
        switch self {
        case .usage:
            return "--help"
        case .listTests:
            return "--list-tests"
        case .run(let specifier):
            return specifier ?? ""
        case .version: return "--version"
        }
    }
}

private func ==(lhs: Mode, rhs: Mode) -> Bool {
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

private class TestToolOptions: Options {
    var verbosity: Int = 0
    var buildTests: Bool = true
    var colorMode: ColorWrap.Mode = .Auto
    var flags = BuildFlags()
}

/// swift-test tool namespace
public struct SwiftTestTool: SwiftTool {
    let args: [String]

    public init(args: [String]) {
        self.args = args
    }
    
    public func run() {
        do {
            let (mode, opts) = try parseOptions(commandLineArguments: args)
        
            verbosity = Verbosity(rawValue: opts.verbosity)
            colorMode = opts.colorMode

            if let dir = opts.chdir {
                try chdir(dir.asString)
            }

            switch mode {
            case .usage:
                usage()
        
            case .version:
                print(Versioning.currentVersion.completeDisplayString)
        
            case .listTests:
                let testPath = try buildTestsIfNeeded(opts)
                let testSuites = try getTestSuites(path: testPath)
                // Print the tests.
                for testSuite in testSuites {
                    for testCase in testSuite.tests {
                        for test in testCase.tests {
                            print(testCase.name + "/" + test)
                        }
                    }
                }

            case .run(let specifier):
                let testPath = try buildTestsIfNeeded(opts)
                let success = test(path: testPath, xctestArg: specifier)
                exit(success ? 0 : 1)
            }
        } catch Error.buildYAMLNotFound {
            print("error: you must run `swift build` first", to: &stderr)
            exit(1)
        } catch {
            handle(error: error, usage: usage)
        }
    }

    /// Builds the "test" target if enabled in options.
    ///
    /// - Returns: The path to the test binary.
    private func buildTestsIfNeeded(_ opts: TestToolOptions) throws -> AbsolutePath {
        let graph = try loadPackage(at: opts.path.root, opts)
        if opts.buildTests {
            let yaml = try describe(opts.path.build, configuration, graph, flags: opts.flags, toolchain: UserToolchain())
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
            return opts.path.build.appending(RelativePath(configuration.dirname)).appending(component: testProducts[0].name + ".xctest")
        }
    }

    // FIXME: We need to support testing in other build configurations, but need
    // to solve the testability problem first.
    private let configuration = Build.Configuration.debug

    private func usage(_ print: (String) -> Void = { print($0) }) {
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

    private func parseOptions(commandLineArguments args: [String]) throws -> (Mode, TestToolOptions) {
        let (mode, flags): (Mode?, [TestToolFlag]) = try Basic.parseOptions(arguments: args)

        let opts = TestToolOptions()
        for flag in flags {
            switch flag {
            case .chdir(let path):
                opts.chdir = path
            case .verbose(let amount):
                opts.verbosity += amount
            case .xcc(let value):
                opts.flags.cCompilerFlags.append(value)
            case .xld(let value):
                opts.flags.linkerFlags.append(value)
            case .xswiftc(let value):
                opts.flags.swiftCompilerFlags.append(value)
            case .buildPath(let buildPath):
                opts.path.build = buildPath
            case .enableNewResolver:
                opts.enableNewResolver = true
            case .colorMode(let mode):
                opts.colorMode = mode
            case .skipBuild:
                opts.buildTests = false
            }
        }

        return (mode ?? .run(nil), opts)
    }

    /// Executes the XCTest binary with given arguments.
    ///
    /// - Parameters:
    ///     - path: Path to a valid XCTest binary.
    ///     - xctestArg: Arguments to pass to the XCTest binary.
    ///
    /// - Returns: True if execution exited with return code 0.
    private func test(path: AbsolutePath, xctestArg: String? = nil) -> Bool {
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

        // Execute the XCTest with inherited environment as it is convenient to pass senstive
        // information like username, password etc to test cases via environment variables.
        let result: Void? = try? system(args, environment: ProcessInfo.processInfo.environment)
        return result != nil
    }

    /// Locates XCTestHelper tool inside the libexec directory and bin directory.
    /// Note: It is a fatalError if we are not able to locate the tool.
    ///
    /// - Returns: Path to XCTestHelper tool.
    private func xctestHelperPath() -> AbsolutePath {
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
    private func getTestSuites(path: AbsolutePath) throws -> [TestSuite] {
        // Run the correct tool.
      #if os(macOS)
        let tempFile = try TemporaryFile()
        let args = [xctestHelperPath().asString, path.asString, tempFile.path.asString]
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
