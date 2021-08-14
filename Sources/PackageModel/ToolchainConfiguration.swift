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
    public var swiftCompilerPath: AbsolutePath

    /// Extra arguments to pass the Swift compiler (defaults to the empty string).
    public var swiftCompilerFlags: [String]

    /// Environment to pass to the Swift compiler (defaults to the inherited environment).
    public var swiftCompilerEnvironment: [String: String]

    /// SwiftPM library paths.
    public var swiftPMLibrariesLocation: SwiftPMLibrariesLocation

    /// The path to SDK root.
    ///
    /// If provided, it will be passed to the swift interpreter.
    public var sdkRootPath: AbsolutePath?

    /// XCTest Location
    public var xctestPath: AbsolutePath?

    /// Creates the set of manifest resources associated with a `swiftc` executable.
    ///
    /// - Parameters:
    ///     - swiftCompilerPath: The absolute path of the associated swift compiler  executable (`swiftc`).
    ///     - swiftCompilerFlags: Extra flags to pass to the Swift compiler.
    ///     - swiftCompilerEnvironment: Environment variables to pass to the Swift compiler.
    ///     - swiftPMLibrariesRootPath: Custom path for SwiftPM libraries. Computed based on the compiler path by default.
    ///     - sdkRootPath: Optional path to SDK root.
    ///     - xctestPath: Optional path to XCTest.
    public init(
        swiftCompilerPath: AbsolutePath,
        swiftCompilerFlags: [String] = [],
        swiftCompilerEnvironment: [String: String] = ProcessEnv.vars,
        swiftPMLibrariesLocation: SwiftPMLibrariesLocation? = nil,
        sdkRootPath: AbsolutePath? = nil,
        xctestPath: AbsolutePath? = nil
    ) {
        let swiftPMLibrariesLocation = swiftPMLibrariesLocation ?? {
            return .init(swiftCompilerPath: swiftCompilerPath)
        }()

        self.swiftCompilerPath = swiftCompilerPath
        self.swiftCompilerFlags = swiftCompilerFlags
        self.swiftCompilerEnvironment = swiftCompilerEnvironment
        self.swiftPMLibrariesLocation = swiftPMLibrariesLocation
        self.sdkRootPath = sdkRootPath
        self.xctestPath = xctestPath
    }

    // deprecated 8/2021
    @available(*, deprecated, message: "use non-deprecated initializer instead")
    public init(
        swiftCompiler: AbsolutePath,
        swiftCompilerFlags: [String] = [],
        swiftCompilerEnvironment: [String: String] = ProcessEnv.vars,
        libDir: AbsolutePath? = nil,
        binDir: AbsolutePath? = nil,
        sdkRoot: AbsolutePath? = nil,
        xctestLocation: AbsolutePath? = nil
    ) {
        self.init(
            swiftCompilerPath: swiftCompiler,
            swiftCompilerFlags: swiftCompilerFlags,
            swiftCompilerEnvironment: swiftCompilerEnvironment,
            swiftPMLibrariesLocation: libDir.map { .init(root: $0) },
            sdkRootPath: sdkRoot,
            xctestPath: xctestLocation
        )
    }
}

extension ToolchainConfiguration {
    public struct SwiftPMLibrariesLocation {
        public var manifestAPI: AbsolutePath
        public var pluginAPI: AbsolutePath

        public init(manifestAPI: AbsolutePath, pluginAPI: AbsolutePath) {
            self.manifestAPI = manifestAPI
            self.pluginAPI = pluginAPI
        }

        public init(root: AbsolutePath) {
            self.init(
                manifestAPI: root.appending(component: "ManifestAPI"),
                pluginAPI: root.appending(component: "PluginAPI")
            )
        }

        public init(swiftCompilerPath: AbsolutePath) {
            let rootPath = swiftCompilerPath.parentDirectory.parentDirectory.appending(components: "lib", "swift", "pm")
            self.init(root: rootPath)
        }
    }
}
