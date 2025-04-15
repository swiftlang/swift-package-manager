//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

/// A structure that provides information and services from the Swift Package Manager
/// or a developer environment that supports Swift Packages.
///
/// Implement this structure in a plugin host to provide the facilities of your developer
/// environment to the package manager.
public struct PackageManager {
    /// Builds the specified products and targets in a package.
    ///
    /// Any errors encountered during the build are reported in the build result,
    /// as is the log of the build commands that were run. This method throws an
    /// error if the input parameters are invalid or if the package manager can't
    /// start the build.
    ///
    /// The SwiftPM CLI or any developer environment that supports packages
    /// may show the progress of the build as it happens.
    ///
    /// - Parameters:
    ///   - subset: The products and targets to build.
    ///   - parameters: Parameters that control aspects of the build.
    /// - Returns: A build result.
    public func build(
        _ subset: BuildSubset,
        parameters: BuildParameters
    ) throws -> BuildResult {
        // Ask the plugin host to build the specified products and targets, and wait for a response.
        // FIXME: We'll want to make this asynchronous when there is back deployment support for it.
        try sendMessageAndWaitForReply(.buildOperationRequest(subset: .init(subset), parameters: .init(parameters))) {
            guard case .buildOperationResponse(let result) = $0 else { return nil }
            return .init(result)
        }
    }

    /// An enumeration that specifies a subset of products and targets of a package to build.
    public enum BuildSubset {
        /// Build all products and all targets, optionally including test targets.
        ///
        /// If `includingTests` is `true` then this case represents all targets of all products;
        /// otherwise, it represents all non-test targets.
        case all(includingTests: Bool)

        /// Build the product with the specified name.
        case product(String)

        /// Build the target with the specified name.
        case target(String)
    }

    /// Parameters and options for the system to apply during a build.
    public struct BuildParameters {
        /// Whether to build the debug or release configuration.
        public var configuration: BuildConfiguration

        /// The amount of detail to include in the log returned in the build result.
        public var logging: BuildLogVerbosity

        /// Whether to print build logs to the console.
        public var echoLogs: Bool

        /// A list of additional flags to pass to all C compiler invocations.
        public var otherCFlags: [String] = []

        /// A list of additional flags to pass to all C++ compiler invocations.
        public var otherCxxFlags: [String] = []

        /// A list of additional flags to pass to all Swift compiler invocations.
        public var otherSwiftcFlags: [String] = []

        /// A list of additional flags to pass to all linker invocations.
        public var otherLinkerFlags: [String] = []

        /// Initializes a build parameters structure.
        ///
        /// - Parameters:
        ///   - configuration: Whether to build the debug or release configuration.
        ///   - logging: The amount of detail to include in the build log.
        ///   - echoLogs: Whether to display build logs while the build is in progress.
        public init(
            configuration: BuildConfiguration = .debug,
            logging: BuildLogVerbosity = .concise,
            echoLogs: Bool = false
        ) {
            self.configuration = configuration
            self.logging = logging
            self.echoLogs = echoLogs
        }
    }

    /// An enumeration that represents the build's purpose.
    ///
    /// The build's purpose affects whether the system
    /// generates debugging symbols, and enables compiler optimizations..
    public enum BuildConfiguration: String {
        /// The build is for debugging.
        case debug
        /// The build is for release.
        case release
        /// The build is a dependency and its purpose is inherited from the build that causes it.
        case inherit
    }

    /// An enumeration that represents the amount of detail
    /// the system includes in a build log.
    public enum BuildLogVerbosity: String {
        /// The build log should be concise.
        case concise
        /// The build log should be verbose.
        case verbose
        /// The build log should include debugging information.
        case debug
    }

    /// An object that represents the results of running a build.
    public struct BuildResult {
        /// A Boolean vaule that indicates whether the build succeeded or failed.
        public var succeeded: Bool

        /// A string that contains the build's log output.
        public var logText: String

        /// A list of the artifacts built from the products in the package.
        ///
        /// Intermediate artificacts, such as object files produced from
        /// individual targets, aren't included in the list.
        public var builtArtifacts: [BuiltArtifact]

        /// An object that represents an artifact produced during a build.
        public struct BuiltArtifact {
            /// The full path to the built artifact in the local file system.
            ///
            /// @DeprecationSummary{Use ``url`` instead.}
            @available(_PackageDescription, deprecated: 6.0, renamed: "url")
            public var path: Path {
                try! Path(url: self.url)
            }

            /// A URL that locates the built artifact in the local file system.
            @available(_PackageDescription, introduced: 6.0)
            public var url: URL

            /// The build artificact's kind.
            public var kind: Kind

            /// An enumeration that represents the kind of a built artifact.
            ///
            /// The specific file
            /// formats may vary from platform to platform — for example, on macOS
            /// a dynamic library may be built as a framework.
            public enum Kind: String {
                /// The artifact is an executable.
                case executable
                /// The artifact is a dynamic library.
                case dynamicLibrary
                /// The artifact is a static library.
                case staticLibrary
            }
        }
    }

    /// Runs the tests in the specified subset.
    ///
    /// As with the `swift test` command, this method performs
    /// an incremental build if necessary before it runs the tests.
    ///
    /// Any test failures are reported in the test result. This method throws an
    /// error if the input parameters are invalid, or it can't start the test.
    ///
    /// The SwiftPM command-line program, or an IDE that supports packages,
    /// may show the progress of the tests as they happen.
    ///
    /// - Parameters:
    ///   - subset: The tests to run.
    ///   - parameters: Parameters that control how the system runs the tests.
    /// - Returns: The outcome of running the tests.
    public func test(
        _ subset: TestSubset,
        parameters: TestParameters
    ) throws -> TestResult {
        // Ask the plugin host to run the specified tests, and wait for a response.
        // FIXME: We'll want to make this asynchronous when there is back deployment support for it.
        try sendMessageAndWaitForReply(.testOperationRequest(subset: .init(subset), parameters: .init(parameters))) {
            guard case .testOperationResponse(let result) = $0 else { return nil }
            return .init(result)
        }
    }

    /// An enumeration that specifies what tests in a package the system runs.
    public enum TestSubset {
        /// All tests in the package.
        case all

        /// One or more tests filtered by regular expression.
        ///
        /// Identify tests using the format `<test-target>.<test-case>`,
        /// or `<test-target>.<test-case>/<test>`.
        /// The `--filter` option of `swift test` uses the same format.
        case filtered([String])
    }

    /// Parameters that control how the system runs tests.
    public struct TestParameters {
        /// A Boolean that tells the system whether to collect code coverage information.
        public var enableCodeCoverage: Bool

        /// Initializes a test parameter structure.
        /// - Parameter enableCodeCoverage: Whether the system collects code coverage information.
        public init(enableCodeCoverage: Bool = false) {
            self.enableCodeCoverage = enableCodeCoverage
        }
    }

    /// A structure that represents the result of running tests.
    public struct TestResult {
        /// A Boolean that indicates whether the test run succeeded.
        public var succeeded: Bool

        /// A list of results for each of the test targets run.
        ///
        /// If the system ran a filtered subset of tests, only results
        /// for the test targets that include the filtered tests are included.
        public var testTargets: [TestTarget]

        /// The optional path to a code coverage file.
        ///
        /// @DeprecationSummary{Use ``codeCoverageDataFileURL`` instead.}
        ///
        /// The file is a generated `.profdata` file suitable for processing using
        /// `llvm-cov`, if ``PackageManager/TestParameters/enableCodeCoverage``
        /// is `true` in the test parameters. If it's `false`, this value is `nil`.
        @available(_PackageDescription, deprecated: 6.0, renamed: "codeCoverageDataFileURL")
        public var codeCoverageDataFile: Path? {
            self.codeCoverageDataFileURL.map { try! Path(url: $0) }
        }

        /// The optional location of a code coverage file.
        ///
        /// The file is a generated `.profdata` file suitable for processing using
        /// `llvm-cov`, if ``PackageManager/TestParameters/enableCodeCoverage``
        /// is `true` in the test parameters. If it's `false`, this value is `nil`.
        @available(_PackageDescription, introduced: 6.0)
        public var codeCoverageDataFileURL: URL?

        /// A structure that represents the results of running tests in a single test target.
        ///
        /// If you use ``PackageManager/TestSubset/filtered(_:)`` to run a filtered
        /// subset of tests, this structure contains results only for tests in
        /// the target that match the filter regex.
        public struct TestTarget {
            /// The test target's name.
            public var name: String
            /// A list of results for test cases defined in the test target.
            public var testCases: [TestCase]

            /// A structure that represents the results of running tests in a
            /// single test case.
            ///
            /// If you use ``PackageManager/TestSubset/filtered(_:)`` to run a filtered
            /// subset of tests, this structure contains results only for tests in
            /// the test case that match the filter regex.
            public struct TestCase {
                /// The test case's name.
                public var name: String
                /// A list of results for tests defined in the test case.
                public var tests: [Test]

                /// A structure that represents the result of running a single test.
                public struct Test {
                    /// The test's name.
                    public var name: String
                    /// The test's outcome.
                    public var result: Result
                    /// The time taken for the system to run the test.
                    public var duration: Double

                    /// An enumeration that represents the result of running a single test.
                    public enum Result: String {
                        /// The test succeeded.
                        case succeeded
                        /// The system skipped the test.
                        case skipped
                        /// The test failed.
                        case failed
                    }
                }
            }
        }
    }

    /// Returns a directory containing symbol graph files for the specified target.
    ///
    /// This method directs the package manager or IDE to create or update the
    /// symbol graphs, if it needs to. How the system creates or updates these
    /// files depends on the implementation of the package manager or IDE.
    /// - Parameters:
    ///   - target: The target for which to generate symbol graphs.
    ///   - options: Options that control how the system generates the symbol graphs.
    /// - Returns: The symbol graphs.
    public func getSymbolGraph(
        for target: Target,
        options: SymbolGraphOptions
    ) throws -> SymbolGraphResult {
        // Ask the plugin host for symbol graph information for the target, and wait for a response.
        // FIXME: We'll want to make this asynchronous when there is back deployment support for it.
        try sendMessageAndWaitForReply(.symbolGraphRequest(targetName: target.name, options: .init(options))) {
            guard case .symbolGraphResponse(let result) = $0 else { return nil }
            return .init(result)
        }
    }

    /// A structure that contains options for controlling how the system generates symbol graphs.
    public struct SymbolGraphOptions {
        /// The symbol graph includes symbols at this access level and higher.
        public var minimumAccessLevel: AccessLevel

        /// An enumeration that represents a symbol access level in Swift.
        public enum AccessLevel: String, CaseIterable {
            /// The symbol is private.
            case `private`
            /// The symbol is file-private.
            case `fileprivate`
            /// The symbol is internal.
            case `internal`
            /// The symbol has package-level visibility.
            case `package`
            /// The symbol is public.
            case `public`
            /// The symbol is open.
            case open
        }

        /// A Boolean value that indicates whether the symbol graph includes synthesized members.
        public var includeSynthesized: Bool

        /// A Boolean value that indicates whether the symbol graph includes symbols marked as SPI.
        public var includeSPI: Bool

        /// A Boolean value that indicates whether the symbol graph includes symbols for extensions to external types.
        public var emitExtensionBlocks: Bool

        /// Initializes a symbol graph options structure.
        /// - Parameters:
        ///   - minimumAccessLevel: The lowest access level to include in the symbol graph.
        ///   - includeSynthesized: Whether to include synthesized symbols in the symbol graph.
        ///   - includeSPI: Whether to include symbols marked as SPI in the symbol graph.
        ///   - emitExtensionBlocks: Whether to include symbols for extensions to external types in the symbol graph.
        public init(
            minimumAccessLevel: AccessLevel = .public,
            includeSynthesized: Bool = false,
            includeSPI: Bool = false,
            emitExtensionBlocks: Bool = false
        ) {
            self.minimumAccessLevel = minimumAccessLevel
            self.includeSynthesized = includeSynthesized
            self.includeSPI = includeSPI
            self.emitExtensionBlocks = emitExtensionBlocks
        }
    }

    /// A structure that represents the result of generating a symbol graph.
    public struct SymbolGraphResult {
        /// A path to a directory that contains the symbol graph files.
        ///
        /// @DeprecationSummary{Use ``directoryURL`` instead.}
        @available(_PackageDescription, deprecated: 6.0, renamed: "directoryURL")
        public var directoryPath: Path {
            try! Path(url: self.directoryURL)
        }

        /// A URL that locates a directory that contains the symbol graph files.
        @available(_PackageDescription, introduced: 6.0)
        public var directoryURL: URL
    }
}

extension PackageManager {
    /// Private helper function that sends a message to the host and waits for a reply. The reply handler should return
    /// `nil` for any reply message it doesn't recognize.
    private func sendMessageAndWaitForReply<T>(
        _ message: PluginToHostMessage,
        replyHandler: (HostToPluginMessage) -> T?
    ) throws -> T {
        try pluginHostConnection.sendMessage(message)
        guard let reply = try pluginHostConnection.waitForNextMessage() else {
            throw PackageManagerProxyError.unspecified("internal error: unexpected lack of response message")
        }
        if case .errorResponse(let message) = reply {
            throw PackageManagerProxyError.unspecified(message)
        }
        if let result = replyHandler(reply) {
            return result
        }
        throw PackageManagerProxyError.unspecified("internal error: unexpected response message \(message)")
    }
}

/// Errors the package manager encounters communicating with its host application.
public enum PackageManagerProxyError: Error {
    /// The functionality isn't implemented in the plugin host.
    case unimplemented(_ message: String)

    /// The package manager proxy encountered an unspecified error.
    case unspecified(_ message: String)
}

extension PluginToHostMessage.BuildSubset {
    fileprivate init(_ subset: PackageManager.BuildSubset) {
        switch subset {
        case .all(let includingTests):
            self = .all(includingTests: includingTests)
        case .product(let name):
            self = .product(name)
        case .target(let name):
            self = .target(name)
        }
    }
}

extension PluginToHostMessage.BuildParameters {
    fileprivate init(_ parameters: PackageManager.BuildParameters) {
        self.configuration = .init(parameters.configuration)
        self.logging = .init(parameters.logging)
        self.echoLogs = parameters.echoLogs
        self.otherCFlags = parameters.otherCFlags
        self.otherCxxFlags = parameters.otherCxxFlags
        self.otherSwiftcFlags = parameters.otherSwiftcFlags
        self.otherLinkerFlags = parameters.otherLinkerFlags
    }
}

extension PluginToHostMessage.BuildParameters.Configuration {
    fileprivate init(_ configuration: PackageManager.BuildConfiguration) {
        switch configuration {
        case .debug:
            self = .debug
        case .release:
            self = .release
        case .inherit:
            self = .inherit
        }
    }
}

extension PluginToHostMessage.BuildParameters.LogVerbosity {
    fileprivate init(_ verbosity: PackageManager.BuildLogVerbosity) {
        switch verbosity {
        case .concise:
            self = .concise
        case .verbose:
            self = .verbose
        case .debug:
            self = .debug
        }
    }
}

extension PackageManager.BuildResult {
    fileprivate init(_ result: HostToPluginMessage.BuildResult) {
        self.succeeded = result.succeeded
        self.logText = result.logText
        self.builtArtifacts = result.builtArtifacts.map { .init($0) }
    }
}

extension PackageManager.BuildResult.BuiltArtifact {
    fileprivate init(_ artifact: HostToPluginMessage.BuildResult.BuiltArtifact) {
        self.kind = .init(artifact.kind)
        self.url = artifact.path
    }
}

extension PackageManager.BuildResult.BuiltArtifact.Kind {
    fileprivate init(_ kind: HostToPluginMessage.BuildResult.BuiltArtifact.Kind) {
        switch kind {
        case .executable:
            self = .executable
        case .dynamicLibrary:
            self = .dynamicLibrary
        case .staticLibrary:
            self = .staticLibrary
        }
    }
}

extension PluginToHostMessage.TestSubset {
    fileprivate init(_ subset: PackageManager.TestSubset) {
        switch subset {
        case .all:
            self = .all
        case .filtered(let regexes):
            self = .filtered(regexes)
        }
    }
}

extension PluginToHostMessage.TestParameters {
    fileprivate init(_ parameters: PackageManager.TestParameters) {
        self.enableCodeCoverage = parameters.enableCodeCoverage
    }
}

extension PackageManager.TestResult {
    fileprivate init(_ result: HostToPluginMessage.TestResult) {
        self.succeeded = result.succeeded
        self.testTargets = result.testTargets.map { .init($0) }
        self.codeCoverageDataFileURL = result.codeCoverageDataFile.map { URL(fileURLWithPath: $0) }
    }
}

extension PackageManager.TestResult.TestTarget {
    fileprivate init(_ testTarget: HostToPluginMessage.TestResult.TestTarget) {
        self.name = testTarget.name
        self.testCases = testTarget.testCases.map { .init($0) }
    }
}

extension PackageManager.TestResult.TestTarget.TestCase {
    fileprivate init(_ testCase: HostToPluginMessage.TestResult.TestTarget.TestCase) {
        self.name = testCase.name
        self.tests = testCase.tests.map { .init($0) }
    }
}

extension PackageManager.TestResult.TestTarget.TestCase.Test {
    fileprivate init(_ test: HostToPluginMessage.TestResult.TestTarget.TestCase.Test) {
        self.name = test.name
        self.result = .init(test.result)
        self.duration = test.duration
    }
}

extension PackageManager.TestResult.TestTarget.TestCase.Test.Result {
    fileprivate init(_ result: HostToPluginMessage.TestResult.TestTarget.TestCase.Test.Result) {
        switch result {
        case .succeeded:
            self = .succeeded
        case .skipped:
            self = .skipped
        case .failed:
            self = .failed
        }
    }
}

extension PluginToHostMessage.SymbolGraphOptions {
    fileprivate init(_ options: PackageManager.SymbolGraphOptions) {
        self.minimumAccessLevel = .init(options.minimumAccessLevel)
        self.includeSynthesized = options.includeSynthesized
        self.includeSPI = options.includeSPI
        self.emitExtensionBlocks = options.emitExtensionBlocks
    }
}

extension PluginToHostMessage.SymbolGraphOptions.AccessLevel {
    fileprivate init(_ accessLevel: PackageManager.SymbolGraphOptions.AccessLevel) {
        switch accessLevel {
        case .private:
            self = .private
        case .fileprivate:
            self = .fileprivate
        case .internal:
            self = .internal
        case .public:
            self = .public
        case .package:
            self = .package
        case .open:
            self = .open
        }
    }
}

extension PackageManager.SymbolGraphResult {
    fileprivate init(_ result: HostToPluginMessage.SymbolGraphResult) {
        self.directoryURL = result.directoryPath
    }
}
