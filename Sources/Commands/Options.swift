/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import TSCUtility
import PackageModel
import SPMBuildCore
import Build

public class ToolOptions {
    /// Custom arguments to pass to C compiler, swift compiler and the linker.
    public var buildFlags = BuildFlags()

    /// Build configuration.
    public var configuration: BuildConfiguration = .debug

    /// The custom build directory, if provided.
    public var buildPath: AbsolutePath?

    /// The custom working directory that the tool should operate in (deprecated).
    public var chdir: AbsolutePath?

    /// The custom working directory that the tool should operate in.
    public var packagePath: AbsolutePath?

    /// The path to the file containing multiroot package data. This is currently Xcode's workspace file.
    public var multirootPackageDataFile: AbsolutePath?

    /// Enable prefetching in resolver which will kick off parallel git cloning.
    public var shouldEnableResolverPrefetching = true

    /// If print version option was passed.
    public var shouldPrintVersion: Bool = false

    /// The verbosity of informational output.
    public var verbosity: Int = 0

    /// Disables sandboxing when executing subprocesses.
    public var shouldDisableSandbox = false

    /// Disables manifest caching.
    public var shouldDisableManifestCaching = false

    /// Path to the compilation destination describing JSON file.
    public var customCompileDestination: AbsolutePath?
    /// The compilation destination’s target triple.
    public var customCompileTriple: Triple?
    /// Path to the compilation destination’s SDK.
    public var customCompileSDK: AbsolutePath?
    /// Path to the compilation destination’s toolchain.
    public var customCompileToolchain: AbsolutePath?

    /// If should link the Swift stdlib statically.
    public var shouldLinkStaticSwiftStdlib = false

    /// Skip updating dependencies from their remote during a resolution.
    public var skipDependencyUpdate = false

    /// Which compile-time sanitizers should be enabled.
    public var sanitizers = EnabledSanitizers()

    /// Whether to enable code coverage.
    public var shouldEnableCodeCoverage = false

    /// Use Package.resolved file for resolving dependencies.
    public var forceResolvedVersions = false

    /// The mode to use for indexing-while-building feature.
    public var indexStoreMode: BuildParameters.IndexStoreMode = .auto

    /// Whether to enable generation of `.swiftinterface`s alongside `.swiftmodule`s.
    public var shouldEnableParseableModuleInterfaces = false

    /// Write dependency resolver trace to a file.
    public var enableResolverTrace = false

    /// The number of jobs for llbuild to start (aka the number of schedulerLanes)
    public var jobs: UInt32? = nil

    /// Whether to enable test discovery on platforms without Objective-C runtime.
    public var enableTestDiscovery: Bool = false

    /// Whether to enable llbuild manifest caching.
    public var enableBuildManifestCaching: Bool = false

    /// Emit the Swift module separately from the object files.
    public var emitSwiftModuleSeparately: Bool = false

    /// The build system to use.
    public var buildSystem: BuildSystemKind = .native

    /// Extra arguments to pass when using xcbuild.
    public var xcbuildFlags: [String] = []

    public required init() {}
}

public enum BuildSystemKind: String, ArgumentKind {
    case native
    case xcode

    public init(argument: String) throws {
        if let kind = BuildSystemKind(rawValue: argument) {
            self = kind
        } else {
            throw ArgumentConversionError.typeMismatch(value: argument, expectedType: BuildSystemKind.self)
        }
    }

    public static var completion: ShellCompletion {
        return .values([
            (value: "native", description: "Native build system"),
            (value: "xcode", description: "Xcode build system"),
        ])
    }
}
