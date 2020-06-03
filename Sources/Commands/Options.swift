/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import ArgumentParser
import TSCBasic
import TSCUtility
import PackageModel
import SPMBuildCore
import Build

struct BuildFlagsGroup: ParsableArguments {
    @Option(name: .customLong("Xcc", withSingleDash: true),
            parsing: .unconditionalSingleValue,
            help: "Pass flag through to all C compiler invocations")
    var cCompilerFlags: [String]
    
    @Option(name: .customLong("Xswiftc", withSingleDash: true),
            parsing: .unconditionalSingleValue,
            help: "Pass flag through to all Swift compiler invocations")
    var swiftCompilerFlags: [String]
    
    @Option(name: .customLong("Xlinker", withSingleDash: true),
            parsing: .unconditionalSingleValue,
            help: "Pass flag through to all linker invocations")
    var linkerFlags: [String]
    
    @Option(name: .customLong("Xccxx", withSingleDash: true),
            parsing: .unconditionalSingleValue,
            help: "Pass flag through to all C++ compiler invocations")
    var cxxCompilerFlags: [String]
    
    @Option(name: .customLong("Xxcbuild", withSingleDash: true),
            parsing: .unconditionalSingleValue,
            help: "Pass flag through to the Xcode build system invocations")
    var xcbuildFlags: [String]
    
    var buildFlags: BuildFlags {
        BuildFlags(
            xcc: cCompilerFlags,
            xcxx: cxxCompilerFlags,
            xswiftc: swiftCompilerFlags,
            xlinker: linkerFlags)
    }
    
    init() {}
}

extension BuildConfiguration: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument)
    }
}

enum BuildSystemKind: String, ExpressibleByArgument {
    case native
    case xcode
}

public struct SwiftToolOptions: ParsableArguments {
    @OptionGroup()
    var buildFlagsGroup: BuildFlagsGroup
    
    /// Custom arguments to pass to C compiler, swift compiler and the linker.
    var buildFlags: BuildFlags {
        buildFlagsGroup.buildFlags
    }

    var xcbuildFlags: [String] {
        buildFlagsGroup.xcbuildFlags
    }
    
    /// Build configuration.
    @Option(name: .shortAndLong, default: .debug, help: "Build with configuration")
    var configuration: BuildConfiguration

    /// The custom build directory, if provided.
    @Option(help: "Specify build/cache directory",
            transform: { try PathArgument(argument: $0).path })
    var buildPath: AbsolutePath?

    /// The custom working directory that the tool should operate in (deprecated).
    @Option(name: [.long, .customShort("C")],
            transform: { try PathArgument(argument: $0).path })
    var chdir: AbsolutePath?

    /// The custom working directory that the tool should operate in.
    @Option(help: "Change working directory before any other operation",
            transform: { try PathArgument(argument: $0).path })
    var packagePath: AbsolutePath?

    /// The path to the file containing multiroot package data. This is currently Xcode's workspace file.
    @Option(name: .customLong("multiroot-data-file"),
            transform: { try PathArgument(argument: $0).path })
    var multirootPackageDataFile: AbsolutePath?

    /// Enable prefetching in resolver which will kick off parallel git cloning.
    @Flag(name: .customLong("prefetching"), default: true, inversion: .prefixedEnableDisable)
    var shouldEnableResolverPrefetching: Bool

    // FIXME: We need to allow -vv type options for this.
    /// The verbosity of informational output.
    @Flag(name: .shortAndLong, help: "Increase verbosity of informational output")
    var verbose: Bool
    
    var verbosity: Int { verbose ? 1 : 0 }

    /// Disables sandboxing when executing subprocesses.
    @Flag(name: .customLong("disable-sandbox"), help: "Disable using the sandbox when executing subprocesses")
    var shouldDisableSandbox: Bool

    /// Disables manifest caching.
    @Flag(name: .customLong("disable-package-manifest-caching"), help: "Disable caching Package.swift manifests")
    var shouldDisableManifestCaching: Bool

    /// Path to the compilation destination describing JSON file.
    @Option(name: .customLong("destination"), transform: { try PathArgument(argument: $0).path })
    var customCompileDestination: AbsolutePath?

    /// The compilation destination’s target triple.
    @Option(name: .customLong("triple"), transform: Triple.init)
    var customCompileTriple: Triple?
    
    /// Path to the compilation destination’s SDK.
    @Option(name: .customLong("sdk"), transform: { try PathArgument(argument: $0).path })
    var customCompileSDK: AbsolutePath?
    
    /// Path to the compilation destination’s toolchain.
    @Option(name: .customLong("toolchain"), transform: { try PathArgument(argument: $0).path })
    var customCompileToolchain: AbsolutePath?

    /// If should link the Swift stdlib statically.
    @Flag(name: .customLong("static-swift-stdlib"), default: false, inversion: .prefixedNo, help: "Link Swift stdlib statically")
    var shouldLinkStaticSwiftStdlib: Bool

    /// Skip updating dependencies from their remote during a resolution.
    @Flag(name: .customLong("skip-update"), help: "Skip updating dependencies from their remote during a resolution")
    var skipDependencyUpdate: Bool

    /// Which compile-time sanitizers should be enabled.
    @Option(name: .customLong("sanitize"),
            help: "Turn on runtime checks for erroneous behavior",
            transform: { try Sanitizer(argument: $0) })
    var sanitizers: [Sanitizer]

    var enabledSanitizers: EnabledSanitizers {
        EnabledSanitizers(Set(sanitizers))
    }
    
    /// Whether to enable code coverage.
    @Flag(name: .customLong("enable-code-coverage"), help: "Test with code coverage enabled")
    var shouldEnableCodeCoverage: Bool

    // TODO: Does disable-automatic-resolution alias force-resolved-versions?
    
    /// Use Package.resolved file for resolving dependencies.
    @Flag(name: [.long, .customLong("disable-automatic-resolution")], help: "Disable automatic resolution if Package.resolved file is out-of-date")
    var forceResolvedVersions: Bool

    @Flag(name: .customLong("index-store"), inversion: .prefixedEnableDisable, help: "Enable or disable  indexing-while-building feature")
    var indexStoreEnable: Bool?
    
    /// The mode to use for indexing-while-building feature.
    var indexStore: BuildParameters.IndexStoreMode {
        guard let enable = indexStoreEnable else { return .auto }
        return enable ? .on : .off
    }
    
    /// Whether to enable generation of `.swiftinterface`s alongside `.swiftmodule`s.
    @Flag(name: .customLong("enable-parseable-module-interfaces"))
    var shouldEnableParseableModuleInterfaces: Bool

    /// Write dependency resolver trace to a file.
    @Flag(name: .customLong("trace-resolver"))
    var enableResolverTrace: Bool

    /// The number of jobs for llbuild to start (aka the number of schedulerLanes)
    @Option(name: .shortAndLong, help: "The number of jobs to spawn in parallel during the build process")
    var jobs: UInt32?

    /// Whether to enable test discovery on platforms without Objective-C runtime.
    @Flag(help: "Enable test discovery on platforms without Objective-C runtime")
    var enableTestDiscovery: Bool

    /// Whether to enable llbuild manifest caching.
    @Flag()
    var enableBuildManifestCaching: Bool

    /// Emit the Swift module separately from the object files.
    @Flag()
    var emitSwiftModuleSeparately: Bool

    /// Whether to use the integrated Swift driver rather than shelling out
    /// to a separate process.
    @Flag()
    var useIntegratedSwiftDriver: Bool

    /// The build system to use.
    @Option(default: .native)
    var buildSystem: BuildSystemKind
    
    public init() {}
}
