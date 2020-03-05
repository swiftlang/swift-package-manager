/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func XCTest.XCTFail
import class Foundation.ProcessInfo

import TSCBasic
import TSCUtility

#if os(macOS)
import class Foundation.Bundle
#endif

public enum SwiftPMProductError: Swift.Error {
    case packagePathNotFound
    case executionFailure(error: Swift.Error, output: String, stderr: String)
}

/// Defines the executables used by SwiftPM.
/// Contains path to the currently built executable and
/// helper method to execute them.
public protocol Product {
    var exec: RelativePath { get }
}

extension Product {
    /// Path to currently built binary.
    public var path: AbsolutePath {
      #if os(macOS)
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return AbsolutePath(bundle.bundlePath).parentDirectory.appending(self.exec)
        }
        fatalError()
      #else
        return AbsolutePath(CommandLine.arguments.first!, relativeTo: localFileSystem.currentWorkingDirectory!)
            .parentDirectory.appending(self.exec)
      #endif
    }

    /// Executes the product with specified arguments.
    ///
    /// - Parameters:
    ///         - args: The arguments to pass.
    ///         - env: Additional environment variables to pass. The values here are merged with default env.
    ///         - packagePath: Adds argument `--package-path <path>` if not nil.
    ///
    /// - Returns: The output of the process.
    @discardableResult
    public func execute(
        _ args: [String],
        packagePath: AbsolutePath? = nil,
        env: [String: String]? = nil
    ) throws -> (stdout: String, stderr: String) {

        let result = try executeProcess(
            args, packagePath: packagePath,
            env: env)

        let output = try result.utf8Output()
        let stderr = try result.utf8stderrOutput()

        if result.exitStatus == .terminated(code: 0) {
            return (stdout: output, stderr: stderr)
        }
        throw SwiftPMProductError.executionFailure(
            error: ProcessResult.Error.nonZeroExit(result),
            output: output,
            stderr: stderr
        )
    }

    public func executeProcess(
        _ args: [String],
        packagePath: AbsolutePath? = nil,
        env: [String: String]? = nil
    ) throws -> ProcessResult {

        var environment = ProcessInfo.processInfo.environment
        for (key, value) in (env ?? [:]) {
            environment[key] = value
        }
      #if Xcode
         // Unset these variables which causes issues when running tests via Xcode.
        environment["XCTestConfigurationFilePath"] = nil
        environment["NSUnbufferedIO"] = nil
      #endif
        // FIXME: We use this private environment variable hack to be able to
        // create special conditions in swift-build for swiftpm tests.
        environment["SWIFTPM_TESTS_MODULECACHE"] = self.path.parentDirectory.pathString
        environment["SDKROOT"] = nil

        // Unset the internal env variable that allows skipping certain tests.
        environment["_SWIFTPM_SKIP_TESTS_LIST"] = nil

        var completeArgs = [path.pathString]
        if let packagePath = packagePath {
            completeArgs += ["--package-path", packagePath.pathString]
        }
        completeArgs += args

        return try Process.popen(arguments: completeArgs, environment: environment)
    }

    public static func packagePath(for packageName: String, packageRoot: AbsolutePath) throws -> AbsolutePath {
        // FIXME: The directory paths are hard coded right now and should be replaced by --get-package-path
        // whenever we design that. https://bugs.swift.org/browse/SR-2753
        let packagesPath = packageRoot.appending(components: ".build", "checkouts")
        for name in try localFileSystem.getDirectoryContents(packagesPath) {
            if name.hasPrefix(packageName) {
                return packagesPath.appending(RelativePath(name))
            }
        }
        throw SwiftPMProductError.packagePathNotFound
    }
}

public struct TestSupportProduct: Product {
    public var exec: RelativePath {
        return RelativePath("TSCTestSupportExecutable")
    }
}

public let TestSupportExecutable = TestSupportProduct()
