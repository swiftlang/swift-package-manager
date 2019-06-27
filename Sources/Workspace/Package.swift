/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import PackageModel
import PackageLoading

extension Package {

    /// Loads a package from a package repository using the resources associated with a particular `swift` executable.
    ///
    /// - Parameters:
    ///     - package: The absolute path of the package root.
    ///     - swiftExecutable: The absolute path of a `swift` executable.
    ///         Its associated resources will be used by the loader.
    public static func loadPackage(
        from package: AbsolutePath,
        with swiftExecutable: AbsolutePath) throws -> Package {

        let manifest = try ManifestLoader.loadManifest(from: package, with: swiftExecutable)
        let builder = PackageBuilder(
            manifest: manifest,
            path: package,
            diagnostics: DiagnosticsEngine(),
            isRootPackage: true)
        return try builder.construct()
    }
}
