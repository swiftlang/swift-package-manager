//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct Basics.AbsolutePath
import struct Basics.Triple
import enum PackageModel.BuildConfiguration

extension BuildParameters {
    /// Represents the test product style.
    public enum TestProductStyle: Encodable {
        /// Test product is a loadable bundle. This style is used on Darwin platforms and, for XCTest tests, relies on the Objective-C
        /// runtime to automatically discover all tests.
        case loadableBundle

        /// Test product is an executable which serves as the testing entry point. This style is used on non-Darwin platforms and,
        /// for XCTests, relies on the testing entry point file to indicate which tests to run. By default, the test entry point file is
        /// synthesized automatically, and uses indexer data to locate all tests and run them. But the entry point may be customized
        /// in one of two ways: if a path to a test entry point file was explicitly passed via the
        /// `--experimental-test-entry-point-path <file>` option, that file is used, otherwise if an `XCTMain.swift`
        /// (formerly `LinuxMain.swift`) file is located in the package, it is used.
        ///
        /// - Parameter explicitlyEnabledDiscovery: Whether test discovery generation was forced by passing
        ///   `--enable-test-discovery`, overriding any custom test entry point file specified via other CLI options or located in
        ///   the package.
        /// - Parameter explicitlySpecifiedPath: The path to the test entry point file, if one was specified explicitly via
        ///   `--experimental-test-entry-point-path <file>`.
        case entryPointExecutable(
            explicitlyEnabledDiscovery: Bool,
            explicitlySpecifiedPath: AbsolutePath?
        )

        /// The explicitly-specified entry point file path, if this style of test product supports it and a path was specified.
        public var explicitlySpecifiedEntryPointPath: AbsolutePath? {
            switch self {
            case .loadableBundle:
                return nil
            case .entryPointExecutable(explicitlyEnabledDiscovery: _, explicitlySpecifiedPath: let entryPointPath):
                return entryPointPath
            }
        }

        public enum DiscriminatorKeys: String, Codable {
            case loadableBundle
            case entryPointExecutable
        }

        public enum CodingKeys: CodingKey {
            case _case
            case explicitlyEnabledDiscovery
            case explicitlySpecifiedPath
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .loadableBundle:
                try container.encode(DiscriminatorKeys.loadableBundle, forKey: ._case)
            case .entryPointExecutable(let explicitlyEnabledDiscovery, let explicitlySpecifiedPath):
                try container.encode(DiscriminatorKeys.entryPointExecutable, forKey: ._case)
                try container.encode(explicitlyEnabledDiscovery, forKey: .explicitlyEnabledDiscovery)
                try container.encode(explicitlySpecifiedPath, forKey: .explicitlySpecifiedPath)
            }
        }
    }

    /// Build parameters related to testing grouped in a single type to aggregate those in one place.
    public struct Testing: Encodable {
        /// Whether to enable code coverage.
        public var enableCodeCoverage: Bool

        /// Whether building for testability is explicitly enabled or disabled.
        package var explicitlyEnabledTestability: Bool?

        /// Whether or not to enable the experimental test output mode.
        public var experimentalTestOutput: Bool

        /// Whether to force test discovery.
        fileprivate var explicitlyEnabledDiscovery: Bool

        /// The path to the test entry point file, if one was specified explicitly
        /// via `--experimental-test-entry-point-path <file>`.
        fileprivate var explicitlySpecifiedPath: AbsolutePath?

        public init(
            enableCodeCoverage: Bool = false,
            enableTestability: Bool? = nil,
            experimentalTestOutput: Bool = false,
            forceTestDiscovery: Bool = false,
            testEntryPointPath: AbsolutePath? = nil
        ) {
            self.enableCodeCoverage = enableCodeCoverage
            self.experimentalTestOutput = experimentalTestOutput
            self.explicitlyEnabledTestability = enableTestability
            self.explicitlyEnabledDiscovery = forceTestDiscovery
            self.explicitlySpecifiedPath = testEntryPointPath
        }
    }

    /// Whether building for testability is enabled.
    public var enableTestability: Bool {
        // decide on testability based on debug/release config
        // the goals of this being based on the build configuration is
        // that `swift build` followed by a `swift test` will need to do minimal rebuilding
        // given that the default configuration for `swift build` is debug
        // and that `swift test` normally requires building with testable enabled.
        // when building and testing in release mode, one can use the '--disable-testable-imports' flag
        // to disable testability in `swift test`, but that requires that the tests do not use the testable imports feature
        self.testingParameters.explicitlyEnabledTestability ?? (self.configuration == .debug)
    }

    /// The style of test product to produce.
    public var testProductStyle: TestProductStyle {
        return triple.isDarwin() ? .loadableBundle : .entryPointExecutable(
            explicitlyEnabledDiscovery: testingParameters.explicitlyEnabledDiscovery,
            explicitlySpecifiedPath: testingParameters.explicitlySpecifiedPath
        )
    }
}
