/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import TSCBasic

/// Toolchain configuration required for evaluation of swift code such as the manifests or plugins
///
/// These requirements are abstracted out to make it easier to add support for
/// using the package manager with alternate toolchains in the future.
public struct ToolchainConfiguration {
    /// The path of the swift compiler.
    public var swiftCompiler: AbsolutePath

    /// Extra arguments to pass the Swift compiler (defaults to the empty string).
    public var swiftCompilerFlags: [String]

    /// Environment to pass to the Swift compiler (defaults to the inherited environment).
    public var swiftCompilerEnvironment: [String: String]

    /// The path of the library resources.
    public var libDir: AbsolutePath

    /// The bin directory.
    public var binDir: AbsolutePath?

    /// The path to SDK root.
    ///
    /// If provided, it will be passed to the swift interpreter.
    public var sdkRoot: AbsolutePath?

    /// XCTest Location
    public var xctestLocation: AbsolutePath?

    /// Creates the set of manifest resources associated with a `swiftc` executable.
    ///
    /// - Parameters:
    ///     - swiftCompiler: The absolute path of the associated `swiftc` executable.
    ///     - swiftCompilerFlags: Extra flags to pass the Swift compiler.: Extra flags to pass the Swift compiler.
    ///     - libDir: The path of the library resources.
    ///     - binDir: The bin directory.
    ///     - sdkRoot: The path to SDK root.
    ///     - xctestLocation: XCTest Location
    public init(
        swiftCompiler: AbsolutePath,
        swiftCompilerFlags: [String] = [],
        swiftCompilerEnvironment: [String: String] = ProcessEnv.vars,
        libDir: AbsolutePath? = nil,
        binDir: AbsolutePath? = nil,
        sdkRoot: AbsolutePath? = nil,
        xctestLocation: AbsolutePath? = nil
    ) {
        self.swiftCompiler = swiftCompiler
        self.swiftCompilerFlags = swiftCompilerFlags
        self.swiftCompilerEnvironment = swiftCompilerEnvironment
        self.libDir = libDir ?? Self.libDir(forBinDir: swiftCompiler.parentDirectory)
        self.binDir = binDir
        self.sdkRoot = sdkRoot
        self.xctestLocation = xctestLocation
    }

    public static func libDir(forBinDir binDir: AbsolutePath) -> AbsolutePath {
        return binDir.parentDirectory.appending(components: "lib", "swift", "pm")
    }
}
