/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func XCTest.XCTFail

import Basic
import POSIX
import Utility

#if os(macOS)
import class Foundation.Bundle
#endif

enum SwiftPMProductError: Swift.Error {
    case packagePathNotFound
}

/// Defines the executables used by SwiftPM.
/// Contains path to the currently built executable and
/// helper method to execute them.
public enum SwiftPMProduct {
    case SwiftBuild
    case SwiftPackage
    case SwiftTest
    case XCTestHelper

    /// Path to currently built binary.
    var path: AbsolutePath {
      #if os(macOS)
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return AbsolutePath(bundle.bundlePath).parentDirectory.appending(self.exec)
        }
        fatalError()
      #else
        return AbsolutePath(CommandLine.arguments.first!, relativeTo: currentWorkingDirectory).parentDirectory.appending(self.exec)
      #endif
    }

    /// Executable name.
    var exec: RelativePath {
        switch self {
        case .SwiftBuild:
            return RelativePath("swift-build")
        case .SwiftPackage:
            return RelativePath("swift-package")
        case .SwiftTest:
            return RelativePath("swift-test")
        case .XCTestHelper:
            return RelativePath("swiftpm-xctest-helper")
        }
    }

    /// Executes the product with specified arguments.
    ///
    /// - Parameters:
    ///         - args: The arguments to pass.
    ///         - env: Environment variables to pass. Environment will never be inherited.
    ///         - chdir: Adds argument `--chdir <path>` if not nil.
    ///         - printIfError: Print the output on non-zero exit.
    ///
    /// - Returns: The output of the process.
    public func execute(_ args: [String], chdir: AbsolutePath? = nil, env: [String: String] = [:], printIfError: Bool = false) throws -> String {
        var out = ""
        var completeArgs = [path.asString]
        // FIXME: Eliminate this when we switch to the new resolver.
        if SwiftPMProduct.enableNewResolver && self != .XCTestHelper {
            completeArgs += ["--enable-new-resolver"]
        }
        if let chdir = chdir {
            completeArgs += ["--chdir", chdir.asString]
        }
        completeArgs += args
        do {
            try POSIX.popen(completeArgs, redirectStandardError: true, environment: env) {
                out += $0
            }
            return out
        } catch {
            if printIfError {
                print("**** FAILURE EXECUTING SUBPROCESS ****")
                print("command: " + completeArgs.map{ $0.shellEscaped() }.joined(separator: " "))
                print("SWIFT_EXEC:", env["SWIFT_EXEC"] ?? "nil")
                print("output:", out)
            }
            throw error
        }
    }

    /// Set this to true to run tests with new resolver.
    public static var enableNewResolver = false

    public static func packagePath(for packageName: String, packageRoot: AbsolutePath) throws -> AbsolutePath {
        // FIXME: The directory paths are hard coded right now and should be replaced by --get-package-path
        // whenever we design that. https://bugs.swift.org/browse/SR-2753
        let packagesPath: AbsolutePath
        if enableNewResolver {
            packagesPath = packageRoot.appending(components: ".build", "checkouts")
        } else {
            packagesPath = packageRoot.appending(component: "Packages")
        }
        for name in try localFileSystem.getDirectoryContents(packagesPath) {
            if name.hasPrefix(packageName) {
                return packagesPath.appending(RelativePath(name))
            }
        }
        throw SwiftPMProductError.packagePathNotFound
    }
}
