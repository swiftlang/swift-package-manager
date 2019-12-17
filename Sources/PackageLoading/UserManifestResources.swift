/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import TSCBasic

/// Concrete object for manifest resource provider.
public struct UserManifestResources: ManifestResourceProvider {
    public let swiftCompiler: AbsolutePath
    public let libDir: AbsolutePath
    public let sdkRoot: AbsolutePath?
    public let binDir: AbsolutePath?

    public init(
        swiftCompiler: AbsolutePath,
        libDir: AbsolutePath,
        sdkRoot: AbsolutePath? = nil,
        binDir: AbsolutePath? = nil
    ) {
        self.swiftCompiler = swiftCompiler
        self.libDir = libDir
        self.sdkRoot = sdkRoot
        self.binDir = binDir
    }

    public static func libDir(forBinDir binDir: AbsolutePath) -> AbsolutePath {
        return binDir.parentDirectory.appending(components: "lib", "swift", "pm")
    }

    /// Creates the set of manifest resources associated with a `swiftc` executable.
    ///
    /// - Parameters:
    ///     - swiftCompiler: The absolute path of the associated `swiftc` executable.
    public init(swiftCompiler: AbsolutePath) throws {
        let binDir = swiftCompiler.parentDirectory
        self.init(
            swiftCompiler: swiftCompiler,
            libDir: UserManifestResources.libDir(forBinDir: binDir))
    }
}
