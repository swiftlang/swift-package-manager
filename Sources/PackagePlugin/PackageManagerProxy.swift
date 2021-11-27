/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

/// Provides specialized information and services from the Swift Package Manager
/// or an IDE that supports Swift Packages. Different plugin hosts implement the
/// functionality in whatever way is appropriate for them, but should preserve
/// the same semantics described here.
public struct PackageManager {

    /// Performs a build of all or a subset of products and targets in a package.
    /// Any errors encountered during the build are reported in the build result.
    /// The SwiftPM CLI or any IDE supporting packages may show the progress of
    /// the build as it happens.
    public func build(
        _ subset: BuildSubset,
        parameters: BuildParameters
    ) -> BuildResult {
        return BuildResult(
            succeeded: false,
            logText: "Unimplemented",
            builtArtifacts: []
        )
    }
    
    /// Specifies a subset of products and targets of a package to build.
    public enum BuildSubset {
        /// Represents the subset consisting of all products and of either all
        /// targets or (if `includingTests` is false) just non-test targets.
        case all(includingTests: Bool)

        /// Represents a specific product.
        case product(String)

        /// Represents a specific target.
        case target(String)
    }
    
    /// Parameters and options to apply during a build.
    public struct BuildParameters {
        /// Whether to build for debug or release.
        public var configuration: BuildConfiguration
        
        /// Controls the amount of detail in the log.
        public var logging: BuildLogVerbosity
        
        // More parameters would almost certainly be added in future proposals.
    }
    
    /// Represents an overall purpose of the build, which affects such things
    /// asoptimization and generation of debug symbols.
    public enum BuildConfiguration {
        case debug
        case release
    }
    
    /// Represents the amount of detail in a log.
    public enum BuildLogVerbosity {
        case concise
        case verbose
        case debug
    }
    
    /// Represents the results of running a build.
    public struct BuildResult {
        /// Whether the build succeeded or failed.
        public var succeeded: Bool
        
        /// Log output (the verbatim text in the initial proposal).
        public var logText: String
        
        /// The artifacts built from the products in the package. Intermediates
        /// such as object files produced from individual targets are not listed.
        public var builtArtifacts: [BuiltArtifact]
        
        /// Represents a single artifact produced during a build.
        public struct BuiltArtifact {
            /// Full path of the built artifact in the local file system.
            public var path: Path
            
            /// The kind of artifact that was built.
            public var kind: Kind
            
            /// Represents the kind of artifact that was built. The specific file
            /// formats may vary from platform to platform — for example, on macOS
            /// a dynamic library may in fact be built as a framework.
            public enum Kind {
                case executable
                case dynamicLibrary
                case staticLibrary
            }
        }
    }
    
    /// Runs all or a specified subset of the unit tests of the package, after
    /// doing an incremental build if necessary.
    public func test(
        _ subset: TestSubset,
        parameters: TestParameters
    ) -> TestResult {
        return TestResult(
            codeCoveragePath: nil
        )
    }
        
    /// Specifies what tests in a package to run.
    public enum TestSubset {
        /// Represents all tests in the package.
        case all

        /// Represents one or more tests filtered by regular expression, with the
        /// format <test-target>.<test-case> or <test-target>.<test-case>/<test>.
        /// This is the same as the `--filter` option of `swift test`.
        case filtered([String])
    }
    
    /// Parameters that control how the test is run.
    public struct TestParameters {
        /// Whether to enable code coverage collection while running the tests.
        public var enableCodeCoverage: Bool
        
        /// There are likely other parameters we would want to add here.
    }
    
    /// Represents the result of running tests.
    public struct TestResult {
        /// Path of the code coverage JSON file, if code coverage was requested.
        public var codeCoveragePath: Path?
        
        /// This should also contain information about the tests that were run
        /// and whether each succeeded/failed.
    }
    
    /// Return a directory containing symbol graph files for the given target
    /// and options. If the symbol graphs need to be created or updated first,
    /// they will be. SwiftPM or an IDE may generate these symbol graph files
    /// in any way it sees fit.
    public func getSymbolGraphDirectory(
        for target: Target,
        options: SymbolGraphOptions
    ) throws -> SymbolGraphInfo {
        try pluginHostConnection.sendMessage(.symbolGraphRequest(targetName: target.name, options: options))
        let message = try pluginHostConnection.waitForNextMessage()
        switch message {
        case .symbolGraphResponse(let info):
            return info
        case .errorResponse(let message):
            throw PackageManagerProxyError.unspecified(message)
        default:
            if let message = message {
                throw PackageManagerProxyError.unspecified("internal error: unexpected response message \(message)")
            }
            else {
                throw PackageManagerProxyError.unspecified("internal error: unexpected lack of response message")
            }
        }
    }

    /// Represents options for symbol graph generation.
    public struct SymbolGraphOptions: Encodable {
        /// The symbol graph will include symbols at this access level and higher.
        public var minimumAccessLevel: AccessLevel

        /// Represents a Swift access level.
        public enum AccessLevel: String, CaseIterable, Encodable {
            case `private`, `fileprivate`, `internal`, `public`, `open`
        }

        /// Whether to include synthesized members.
        public var includeSynthesized: Bool
        
        /// Whether to include symbols marked as SPI.
        public var includeSPI: Bool
        
        public init(minimumAccessLevel: AccessLevel = .public, includeSynthesized: Bool = false, includeSPI: Bool = false) {
            self.minimumAccessLevel = minimumAccessLevel
            self.includeSynthesized = includeSynthesized
            self.includeSPI = includeSPI
        }
    }

    /// Represents results of symbol graph generation.
    public struct SymbolGraphInfo: Decodable {
        /// The directory that contains the symbol graph files for the target.
        public var directoryPath: Path
    }
}

public enum PackageManagerProxyError: Error {
    /// Indicates that the functionality isn't implemented in the plugin host.
    case unimlemented(_ message: String)
    
    /// An unspecified other kind of error from the Package Manager proxy.
    case unspecified(_ message: String)
}
