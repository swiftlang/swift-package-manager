//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import TSCBasic
import PackageFingerprint
import PackageModel
import SPMBuildCore
import Build

import struct TSCUtility.BuildFlags
import struct TSCUtility.Triple

struct GlobalOptions: ParsableArguments {
    init() {}

    @OptionGroup()
    var locations: LocationOptions

    @OptionGroup()
    var caching: CachingOptions

    @OptionGroup()
    var logging: LoggingOptions

    @OptionGroup()
    var security: SecurityOptions

    @OptionGroup()
    var resolver: ResolverOptions

    @OptionGroup()
    var build: BuildOptions

    @OptionGroup()
    var linker: LinkerOptions
}

struct LocationOptions: ParsableArguments {
    init() {}

    @Option(name: .customLong("package-path"), help: "Specify the package path to operate on (default current directory). This changes the working directory before any other operation", completion: .directory)
    var _packageDirectory: AbsolutePath?

    @Option(name: .customLong("cache-path"), help: "Specify the shared cache directory path", completion: .directory)
    var cacheDirectory: AbsolutePath?

    @Option(name: .customLong("config-path"), help: "Specify the shared configuration directory path", completion: .directory)
    var configurationDirectory: AbsolutePath?

    @Option(name: .customLong("security-path"), help: "Specify the shared security directory path", completion: .directory)
    var securityDirectory: AbsolutePath?

    @Option(name: [.long, .customShort("C")], help: .hidden)
    var _deprecated_chdir: AbsolutePath?

    var packageDirectory: AbsolutePath? {
        self._packageDirectory ?? self._deprecated_chdir
    }

    /// The custom .build directory, if provided.
    @Option(name: .customLong("scratch-path"), help: "Specify a custom scratch directory path (default .build)", completion: .directory)
    var _scratchDirectory: AbsolutePath?

    @Option(name: .customLong("build-path"), help: .hidden)
    var _deprecated_buildPath: AbsolutePath?

    var scratchDirectory: AbsolutePath? {
        self._scratchDirectory ?? self._deprecated_buildPath
    }

    /// The path to the file containing multiroot package data. This is currently Xcode's workspace file.
    @Option(name: .customLong("multiroot-data-file"), help: .hidden, completion: .directory)
    var multirootPackageDataFile: AbsolutePath?

    /// Path to the compilation destination describing JSON file.
    @Option(name: .customLong("destination"), help: .hidden, completion: .directory)
    var customCompileDestination: AbsolutePath?
}

struct CachingOptions: ParsableArguments {
    /// Disables package caching.
    @Flag(name: .customLong("dependency-cache"), inversion: .prefixedEnableDisable, help: "Use a shared cache when fetching dependencies")
    var _useDependenciesCache: Bool = true

    // TODO: simplify when deprecating the older flag
    var useDependenciesCache: Bool {
        if let value = self._deprecated_useRepositoriesCache {
            return value
        }  else {
            return self._useDependenciesCache
        }
    }

    /// Disables manifest caching.
    @Flag(name: .customLong("disable-package-manifest-caching"), help: .hidden)
    var shouldDisableManifestCaching: Bool = false

    /// Whether to enable llbuild manifest caching.
    @Flag(name: .customLong("build-manifest-caching"), inversion: .prefixedEnableDisable)
    var cacheBuildManifest: Bool = true

    /// Disables manifest caching.
    @Option(name: .customLong("manifest-cache"), help: "Caching mode of Package.swift manifests (shared: shared cache, local: package's build directory, none: disabled")
    var manifestCachingMode: ManifestCachingMode = .shared

    enum ManifestCachingMode: String, ExpressibleByArgument {
        case none
        case local
        case shared

        init?(argument: String) {
            self.init(rawValue: argument)
        }
    }

    /// Disables repository caching.
    @Flag(name: .customLong("repository-cache"), inversion: .prefixedEnableDisable, help: .hidden)
    var _deprecated_useRepositoriesCache: Bool?
}

struct LoggingOptions: ParsableArguments {
    init() {}

    /// The verbosity of informational output.
    @Flag(name: .shortAndLong, help: "Increase verbosity to include informational output")
    var verbose: Bool = false

    /// The verbosity of informational output.
    @Flag(name: [.long, .customLong("vv")], help: "Increase verbosity to include debug output")
    var veryVerbose: Bool = false
}

struct SecurityOptions: ParsableArguments {
    init() {}

    /// Disables sandboxing when executing subprocesses.
    @Flag(name: .customLong("disable-sandbox"), help: "Disable using the sandbox when executing subprocesses")
    var shouldDisableSandbox: Bool = false

    /// Whether to load .netrc files for authenticating with remote servers
    /// when downloading binary artifacts or communicating with a registry.
    @Flag(inversion: .prefixedEnableDisable,
          exclusivity: .exclusive,
          help: "Load credentials from a .netrc file")
    var netrc: Bool = true

    /// The path to the .netrc file used when `netrc` is `true`.
    @Option(
        name: .customLong("netrc-file"),
        help: "Specify the .netrc file path.",
        completion: .file())
    var netrcFilePath: AbsolutePath?

    /// Whether to use keychain for authenticating with remote servers
    /// when downloading binary artifacts or communicating with a registry.
    #if canImport(Security)
    @Flag(inversion: .prefixedEnableDisable,
          exclusivity: .exclusive,
          help: "Search credentials in macOS keychain")
    var keychain: Bool = true
    #else
    @Flag(inversion: .prefixedEnableDisable,
          exclusivity: .exclusive,
          help: .hidden)
    var keychain: Bool = false
    #endif

    @Option(name: .customLong("resolver-fingerprint-checking"))
    var fingerprintCheckingMode: FingerprintCheckingMode = .strict

    @Flag(name: .customLong("netrc"), help: .hidden)
    var _deprecated_netrc: Bool = false

    @Flag(name: .customLong("netrc-optional"), help: .hidden)
    var _deprecated_netrcOptional: Bool = false
}

struct ResolverOptions: ParsableArguments {
    init() {}

    /// Enable prefetching in resolver which will kick off parallel git cloning.
    @Flag(name: .customLong("prefetching"), inversion: .prefixedEnableDisable)
    var shouldEnableResolverPrefetching: Bool = true

    /// Use Package.resolved file for resolving dependencies.
    @Flag(name: [.long, .customLong("disable-automatic-resolution"), .customLong("only-use-versions-from-resolved-file")], help: "Only use versions from the Package.resolved file and fail resolution if it is out-of-date")
    var forceResolvedVersions: Bool = false

    /// Skip updating dependencies from their remote during a resolution.
    @Flag(name: .customLong("skip-update"), help: "Skip updating dependencies from their remote during a resolution")
    var skipDependencyUpdate: Bool = false


    @Flag(help: "Define automatic transformation of source control based dependencies to registry based ones")
    var sourceControlToRegistryDependencyTransformation: SourceControlToRegistryDependencyTransformation = .disabled

    /// Write dependency resolver trace to a file.
    @Flag(name: .customLong("trace-resolver"), help: .hidden)
    var _deprecated_enableResolverTrace: Bool = false

    enum SourceControlToRegistryDependencyTransformation: EnumerableFlag {
        case disabled
        case identity
        case swizzle

        static func name(for value: Self) -> NameSpecification {
            switch value {
            case .disabled:
                return .customLong("disable-scm-to-registry-transformation")
            case .identity:
                return .customLong("use-registry-identity-for-scm")
            case .swizzle:
                return .customLong("replace-scm-with-registry")
            }
        }

        static func help(for value: SourceControlToRegistryDependencyTransformation) -> ArgumentHelp? {
            switch value {
            case .disabled:
                return "disable source control to registry transformation"
            case .identity:
                return "look up source control dependencies in the registry and use their registry identity when possible to help deduplicate across the two origins"
            case .swizzle:
                return "look up source control dependencies in the registry and use the registry to retrieve them instead of source control when possible"
            }
        }
    }
}

struct BuildOptions: ParsableArguments {
    init() {}

    /// Build configuration.
    @Option(name: .shortAndLong, help: "Build with configuration")
    var configuration: BuildConfiguration = .debug

    @Option(name: .customLong("Xcc", withSingleDash: true),
            parsing: .unconditionalSingleValue,
            help: "Pass flag through to all C compiler invocations")
    var cCompilerFlags: [String] = []

    @Option(name: .customLong("Xswiftc", withSingleDash: true),
            parsing: .unconditionalSingleValue,
            help: "Pass flag through to all Swift compiler invocations")
    var swiftCompilerFlags: [String] = []

    @Option(name: .customLong("Xlinker", withSingleDash: true),
            parsing: .unconditionalSingleValue,
            help: "Pass flag through to all linker invocations")
    var linkerFlags: [String] = []

    @Option(name: .customLong("Xcxx", withSingleDash: true),
            parsing: .unconditionalSingleValue,
            help: "Pass flag through to all C++ compiler invocations")
    var cxxCompilerFlags: [String] = []

    @Option(name: .customLong("Xxcbuild", withSingleDash: true),
            parsing: .unconditionalSingleValue,
            help: ArgumentHelp(
                "Pass flag through to the Xcode build system invocations",
                shouldDisplay: false))
    var xcbuildFlags: [String] = []

    @Option(name: .customLong("Xmanifest", withSingleDash: true),
            parsing: .unconditionalSingleValue,
            help: ArgumentHelp("Pass flag to the manifest build invocation",
                               shouldDisplay: false))
    var manifestFlags: [String] = []

    var buildFlags: BuildFlags {
        BuildFlags(
            xcc: cCompilerFlags,
            xcxx: cxxCompilerFlags,
            xswiftc: swiftCompilerFlags,
            xlinker: linkerFlags)
    }

    /// The compilation destination’s target triple.
    @Option(name: .customLong("triple"), transform: Triple.init)
    var customCompileTriple: Triple?

    /// Path to the compilation destination’s SDK.
    @Option(name: .customLong("sdk"))
    var customCompileSDK: AbsolutePath?

    /// Path to the compilation destination’s toolchain.
    @Option(name: .customLong("toolchain"))
    var customCompileToolchain: AbsolutePath?

    /// The architectures to compile for.
    @Option(
      name: .customLong("arch"),
      help: ArgumentHelp(
        "Build the package for the these architectures",
        shouldDisplay: false))
    public var archs: [String] = []

    /// Which compile-time sanitizers should be enabled.
    @Option(name: .customLong("sanitize"),
            help: "Turn on runtime checks for erroneous behavior, possible values: \(Sanitizer.formattedValues)",
            transform: { try Sanitizer(argument: $0) })
    var sanitizers: [Sanitizer] = []

    var enabledSanitizers: EnabledSanitizers {
        EnabledSanitizers(Set(sanitizers))
    }

    @Flag(help: "Enable or disable indexing-while-building feature")
    var indexStoreMode: StoreMode = .autoIndexStore

    /// Whether to enable generation of `.swiftinterface`s alongside `.swiftmodule`s.
    @Flag(name: .customLong("enable-parseable-module-interfaces"))
    var shouldEnableParseableModuleInterfaces: Bool = false

    /// The number of jobs for llbuild to start (aka the number of schedulerLanes)
    @Option(name: .shortAndLong, help: "The number of jobs to spawn in parallel during the build process")
    var jobs: UInt32?

    /// Emit the Swift module separately from the object files.
    @Flag()
    var emitSwiftModuleSeparately: Bool = false

    /// Whether to use the integrated Swift driver rather than shelling out
    /// to a separate process.
    @Flag()
    var useIntegratedSwiftDriver: Bool = false

    /// A flag that inidcates this build should check whether targets only import
    /// their explicitly-declared dependencies
    @Option()
    var explicitTargetDependencyImportCheck: TargetDependencyImportCheckingMode = .none

    /// Whether to use the explicit module build flow (with the integrated driver)
    @Flag(name: .customLong("experimental-explicit-module-build"))
    var useExplicitModuleBuild: Bool = false

    /// The build system to use.
    @Option(name: .customLong("build-system"))
    var _buildSystem: BuildSystemKind = .native

    var buildSystem: BuildSystemKind {
        #if os(macOS)
        // Force the Xcode build system if we want to build more than one arch.
        return archs.count > 1 ? .xcode : self._buildSystem
        #else
        // Force building with the native build system on other platforms than macOS.
        return .native
        #endif
    }

    /// Whether to enable test discovery on platforms without Objective-C runtime.
    @Flag(help: .hidden)
    var enableTestDiscovery: Bool = false

    // @Flag works best when there is a default value present
    // if true, false aren't enough and a third state is needed
    // nil should not be the goto. Instead create an enum
    enum StoreMode: EnumerableFlag {
        case autoIndexStore
        case enableIndexStore
        case disableIndexStore
    }

    enum BuildSystemKind: String, ExpressibleByArgument, CaseIterable {
        case native
        case xcode
    }

    enum TargetDependencyImportCheckingMode : String, Codable, ExpressibleByArgument {
        case none
        case warn
        case error
    }
}

struct LinkerOptions: ParsableArguments {
    init() {}

    @Flag(
        name: .customLong("dead-strip"),
        inversion: .prefixedEnableDisable,
        help: "Disable/enable dead code stripping by the linker")
    var linkerDeadStrip: Bool = true

    /// If should link the Swift stdlib statically.
    @Flag(name: .customLong("static-swift-stdlib"), inversion: .prefixedNo, help: "Link Swift stdlib statically")
    var shouldLinkStaticSwiftStdlib: Bool = false
}


// MARK: - Extensions


extension BuildConfiguration: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument)
    }
}

extension AbsolutePath: ExpressibleByArgument {
    public init?(argument: String) {
        if let cwd = localFileSystem.currentWorkingDirectory {
            self.init(argument, relativeTo: cwd)
        } else {
            guard let path = try? AbsolutePath(validating: argument) else {
                return nil
            }
            self = path
        }
    }

    public static var defaultCompletionKind: CompletionKind {
        // This type is most commonly used to select a directory, not a file.
        // Specify '.file()' in an argument declaration when necessary.
        .directory
    }
}


extension FingerprintCheckingMode: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument)
    }
}

extension Sanitizer {
    init(argument: String) throws {
        if let sanitizer = Sanitizer(rawValue: argument) {
            self = sanitizer
            return
        }

        for sanitizer in Sanitizer.allCases where sanitizer.shortName == argument {
            self = sanitizer
            return
        }

        throw StringError("valid sanitizers: \(Sanitizer.formattedValues)")
    }

    /// All sanitizer options in a comma separated string
    fileprivate static var formattedValues: String {
        return Sanitizer.allCases.map(\.rawValue).joined(separator: ", ")
    }
}
