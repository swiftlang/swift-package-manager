//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import class Foundation.ProcessInfo
import PackageModel
import PackageGraph

public struct BuildParameters: Encodable {
    /// Mode for the indexing-while-building feature.
    public enum IndexStoreMode: String, Encodable {
        /// Index store should be enabled.
        case on
        /// Index store should be disabled.
        case off
        /// Index store should be enabled in debug configuration.
        case auto
    }

    /// An optional intermodule optimization to run at link time.
    ///
    /// When using Link Time Optimization (LTO for short) the swift and clang
    /// compilers produce objects containing containing a higher level
    /// representation of the program bitcode instead of machine code. The
    /// linker combines these objects together performing additional
    /// optimizations with visibility into each module/object, resulting in a
    /// further optimized version of the executable.
    ///
    /// Using LTO can have significant impact on compile times, however can be
    /// used to dramatically reduce code-size in some cases.
    ///
    /// Note: Bitcode objects and machine code objects can be linked together.
    public enum LinkTimeOptimizationMode: String, Encodable {
        /// The "standard" LTO mode designed to produce minimal code sign.
        ///
        /// Full LTO can lead to large link times. Consider using thin LTO if
        /// build time is more important than minimizing binary size.
        case full
        /// An LTO mode designed to scale better with input size.
        ///
        /// Thin LTO typically results in faster link times than traditional LTO.
        /// However, thin LTO may not result in binary as small as full LTO.
        case thin
    }

    /// Represents the debug information format.
    ///
    /// The debug information format controls the format of the debug information
    /// that the compiler generates.  Some platforms support debug information
    // formats other than DWARF.
    public enum DebugInfoFormat: String, Encodable {
        /// DWARF debug information format, the default format used by Swift.
        case dwarf
        /// CodeView debug information format, used on Windows.
        case codeview
        /// No debug information to be emitted.
        case none
    }

    /// Represents the debugging strategy.
    ///
    /// Swift binaries requires the swiftmodule files in order for lldb to work.
    /// On Darwin, linker can directly take the swiftmodule file path using the
    /// -add_ast_path flag. On other platforms, we convert the swiftmodule into
    /// an object file using Swift's modulewrap tool.
    public enum DebuggingStrategy {
        case swiftAST
        case modulewrap
    }

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

        /// Whether this test product style requires additional, derived test targets, i.e. there must be additional test targets, beyond those
        /// listed explicitly in the package manifest, created in order to add additional behavior (such as entry point logic).
        public var requiresAdditionalDerivedTestTargets: Bool {
            switch self {
            case .loadableBundle:
                return false
            case .entryPointExecutable:
                return true
            }
        }

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

    /// A mode for explicit import checking
    public enum TargetDependencyImportCheckingMode : Codable {
        case none
        case warn
        case error
    }

    /// The path to the data directory.
    public var dataPath: AbsolutePath

    /// The build configuration.
    public var configuration: BuildConfiguration

    /// The toolchain.
    public var toolchain: Toolchain { _toolchain.toolchain }
    private let _toolchain: _Toolchain

    /// Host triple.
    public var hostTriple: Triple

    /// Target triple.
    @available(*, deprecated, renamed: "targetTriple")
    public var triple: Triple {
        get { targetTriple }
        set { targetTriple = newValue }
    }

    /// Target triple.
    public var targetTriple: Triple

    /// Extra build flags.
    public var flags: BuildFlags

    /// An array of paths to search for pkg-config `.pc` files.
    public var pkgConfigDirectories: [AbsolutePath]

    /// The architectures to build for.
    public var architectures: [String]?

    /// How many jobs should llbuild and the Swift compiler spawn
    public var workers: UInt32

    /// If should link the Swift stdlib statically.
    public var shouldLinkStaticSwiftStdlib: Bool

    /// Disables adding $ORIGIN/@loader_path to the rpath, useful when deploying
    public var shouldDisableLocalRpath: Bool

    /// Which compiler sanitizers should be enabled
    public var sanitizers: EnabledSanitizers

    /// If should enable llbuild manifest caching.
    public var shouldEnableManifestCaching: Bool

    /// The mode to use for indexing-while-building feature.
    public var indexStoreMode: IndexStoreMode

    /// Whether to enable code coverage.
    public var enableCodeCoverage: Bool

    /// Whether to enable generation of `.swiftinterface` files alongside.
    /// `.swiftmodule`s.
    public var enableParseableModuleInterfaces: Bool

    /// Whether to use the integrated Swift driver rather than shelling out
    /// to a separate process.
    public var useIntegratedSwiftDriver: Bool

    /// Whether to use the explicit module build flow (with the integrated driver).
    public var useExplicitModuleBuild: Bool

    /// A flag that indicates this build should check whether targets only import.
    /// their explicitly-declared dependencies
    public var explicitTargetDependencyImportCheckingMode: TargetDependencyImportCheckingMode

    /// Whether to create dylibs for dynamic library products.
    public var shouldCreateDylibForDynamicProducts: Bool

    /// Whether to enable the entry-point-function-name feature.
    public var canRenameEntrypointFunctionName: Bool

    /// Whether or not to enable the experimental test output mode.
    public var experimentalTestOutput: Bool

    /// The current build environment.
    public var buildEnvironment: BuildEnvironment {
        BuildEnvironment(platform: currentPlatform, configuration: configuration)
    }

    /// The current platform we're building for.
    var currentPlatform: PackageModel.Platform {
        if self.targetTriple.isDarwin() {
            switch self.targetTriple.darwinPlatform {
            case .iOS(.catalyst):
                return .macCatalyst
            case .iOS(.device), .iOS(.simulator):
                return .iOS
            case .tvOS:
                return .tvOS
            case .watchOS:
                return .watchOS
            case .macOS, nil:
                return .macOS
            }
        } else if self.targetTriple.isAndroid() {
            return .android
        } else if self.targetTriple.isWASI() {
            return .wasi
        } else if self.targetTriple.isWindows() {
            return .windows
        } else if self.targetTriple.isOpenBSD() {
            return .openbsd
        } else {
            return .linux
        }
    }

    /// Whether the Xcode build system is used.
    public var isXcodeBuildSystemEnabled: Bool

    // Whether building for testability is enabled.
    public var enableTestability: Bool

    /// The style of test product to produce.
    public var testProductStyle: TestProductStyle

    /// Whether to disable dead code stripping by the linker
    public var linkerDeadStrip: Bool

    public var colorizedOutput: Bool

    public var verboseOutput: Bool

    public var linkTimeOptimizationMode: LinkTimeOptimizationMode?

    public var debugInfoFormat: DebugInfoFormat

    public var shouldSkipBuilding: Bool

    @available(*, deprecated, message: "use `init` overload with `targetTriple` parameter name instead")
    @_disfavoredOverload
    public init(
        dataPath: AbsolutePath,
        configuration: BuildConfiguration,
        toolchain: Toolchain,
        hostTriple: Triple? = nil,
        destinationTriple: Triple? = nil,
        flags: BuildFlags,
        pkgConfigDirectories: [AbsolutePath] = [],
        architectures: [String]? = nil,
        workers: UInt32 = UInt32(ProcessInfo.processInfo.activeProcessorCount),
        shouldLinkStaticSwiftStdlib: Bool = false,
        shouldEnableManifestCaching: Bool = false,
        canRenameEntrypointFunctionName: Bool = false,
        shouldCreateDylibForDynamicProducts: Bool = true,
        sanitizers: EnabledSanitizers = EnabledSanitizers(),
        enableCodeCoverage: Bool = false,
        indexStoreMode: IndexStoreMode = .auto,
        enableParseableModuleInterfaces: Bool = false,
        useIntegratedSwiftDriver: Bool = false,
        useExplicitModuleBuild: Bool = false,
        isXcodeBuildSystemEnabled: Bool = false,
        enableTestability: Bool? = nil,
        forceTestDiscovery: Bool = false,
        testEntryPointPath: AbsolutePath? = nil,
        explicitTargetDependencyImportCheckingMode: TargetDependencyImportCheckingMode = .none,
        linkerDeadStrip: Bool = true,
        colorizedOutput: Bool = false,
        verboseOutput: Bool = false,
        linkTimeOptimizationMode: LinkTimeOptimizationMode? = nil,
        debugInfoFormat: DebugInfoFormat = .dwarf,
        shouldSkipBuilding: Bool = false,
        experimentalTestOutput: Bool = false
    ) throws {
        try self.init(
            dataPath: dataPath,
            configuration: configuration,
            toolchain: toolchain,
            hostTriple: hostTriple,
            targetTriple: destinationTriple,
            flags: flags,
            pkgConfigDirectories: pkgConfigDirectories,
            architectures: architectures,
            workers: workers,
            shouldLinkStaticSwiftStdlib: shouldLinkStaticSwiftStdlib,
            shouldEnableManifestCaching: shouldEnableManifestCaching,
            canRenameEntrypointFunctionName: canRenameEntrypointFunctionName,
            shouldCreateDylibForDynamicProducts: shouldCreateDylibForDynamicProducts,
            sanitizers: sanitizers,
            enableCodeCoverage: enableCodeCoverage,
            indexStoreMode: indexStoreMode,
            enableParseableModuleInterfaces: enableParseableModuleInterfaces,
            useIntegratedSwiftDriver: useIntegratedSwiftDriver,
            useExplicitModuleBuild: useExplicitModuleBuild,
            isXcodeBuildSystemEnabled: isXcodeBuildSystemEnabled,
            enableTestability: enableTestability,
            forceTestDiscovery: forceTestDiscovery,
            testEntryPointPath: testEntryPointPath,
            explicitTargetDependencyImportCheckingMode: explicitTargetDependencyImportCheckingMode,
            linkerDeadStrip: linkerDeadStrip,
            colorizedOutput: colorizedOutput,
            verboseOutput: verboseOutput,
            linkTimeOptimizationMode: linkTimeOptimizationMode,
            debugInfoFormat: debugInfoFormat,
            shouldSkipBuilding: shouldSkipBuilding,
            experimentalTestOutput: experimentalTestOutput
        )
    }

    public init(
        dataPath: AbsolutePath,
        configuration: BuildConfiguration,
        toolchain: Toolchain,
        hostTriple: Triple? = nil,
        targetTriple: Triple? = nil,
        flags: BuildFlags,
        pkgConfigDirectories: [AbsolutePath] = [],
        architectures: [String]? = nil,
        workers: UInt32 = UInt32(ProcessInfo.processInfo.activeProcessorCount),
        shouldLinkStaticSwiftStdlib: Bool = false,
        shouldDisableLocalRpath: Bool = false,
        shouldEnableManifestCaching: Bool = false,
        canRenameEntrypointFunctionName: Bool = false,
        shouldCreateDylibForDynamicProducts: Bool = true,
        sanitizers: EnabledSanitizers = EnabledSanitizers(),
        enableCodeCoverage: Bool = false,
        indexStoreMode: IndexStoreMode = .auto,
        enableParseableModuleInterfaces: Bool = false,
        useIntegratedSwiftDriver: Bool = false,
        useExplicitModuleBuild: Bool = false,
        isXcodeBuildSystemEnabled: Bool = false,
        enableTestability: Bool? = nil,
        forceTestDiscovery: Bool = false,
        testEntryPointPath: AbsolutePath? = nil,
        explicitTargetDependencyImportCheckingMode: TargetDependencyImportCheckingMode = .none,
        linkerDeadStrip: Bool = true,
        colorizedOutput: Bool = false,
        verboseOutput: Bool = false,
        linkTimeOptimizationMode: LinkTimeOptimizationMode? = nil,
        debugInfoFormat: DebugInfoFormat = .dwarf,
        shouldSkipBuilding: Bool = false,
        experimentalTestOutput: Bool = false
    ) throws {
        let targetTriple = try targetTriple ?? .getHostTriple(usingSwiftCompiler: toolchain.swiftCompilerPath)

        self.dataPath = dataPath
        self.configuration = configuration
        self._toolchain = _Toolchain(toolchain: toolchain)
        self.hostTriple = try hostTriple ?? .getHostTriple(usingSwiftCompiler: toolchain.swiftCompilerPath)
        self.targetTriple = targetTriple
        switch debugInfoFormat {
        case .dwarf:
            var flags = flags
            // DWARF requires lld as link.exe expects CodeView debug info.
            self.flags = flags.merging(targetTriple.isWindows() ? BuildFlags(
                cCompilerFlags: ["-gdwarf"],
                cxxCompilerFlags: ["-gdwarf"],
                swiftCompilerFlags: ["-g", "-use-ld=lld"],
                linkerFlags: ["-debug:dwarf"]
            ) : BuildFlags(cCompilerFlags: ["-g"], cxxCompilerFlags: ["-g"], swiftCompilerFlags: ["-g"]))
        case .codeview:
            if !targetTriple.isWindows() {
                throw StringError("CodeView debug information is currently not supported on \(targetTriple.osName)")
            }
            var flags = flags
            self.flags = flags.merging(BuildFlags(
                cCompilerFlags: ["-g"],
                cxxCompilerFlags: ["-g"],
                swiftCompilerFlags: ["-g", "-debug-info-format=codeview"],
                linkerFlags: ["-debug"]
            ))
        case .none:
            var flags = flags
            self.flags = flags.merging(BuildFlags(
                cCompilerFlags: ["-g0"],
                cxxCompilerFlags: ["-g0"],
                swiftCompilerFlags: ["-gnone"]
            ))
        }
        self.pkgConfigDirectories = pkgConfigDirectories
        self.architectures = architectures
        self.workers = workers
        self.shouldLinkStaticSwiftStdlib = shouldLinkStaticSwiftStdlib
        self.shouldDisableLocalRpath = shouldDisableLocalRpath
        self.shouldEnableManifestCaching = shouldEnableManifestCaching
        self.shouldCreateDylibForDynamicProducts = shouldCreateDylibForDynamicProducts
        self.canRenameEntrypointFunctionName = canRenameEntrypointFunctionName
        self.sanitizers = sanitizers
        self.enableCodeCoverage = enableCodeCoverage
        self.indexStoreMode = indexStoreMode
        self.enableParseableModuleInterfaces = enableParseableModuleInterfaces
        self.useIntegratedSwiftDriver = useIntegratedSwiftDriver
        self.useExplicitModuleBuild = useExplicitModuleBuild
        self.isXcodeBuildSystemEnabled = isXcodeBuildSystemEnabled
        // decide on testability based on debug/release config
        // the goals of this being based on the build configuration is
        // that `swift build` followed by a `swift test` will need to do minimal rebuilding
        // given that the default configuration for `swift build` is debug
        // and that `swift test` normally requires building with testable enabled.
        // when building and testing in release mode, one can use the '--disable-testable-imports' flag
        // to disable testability in `swift test`, but that requires that the tests do not use the testable imports feature
        self.enableTestability = enableTestability ?? (.debug == configuration)
        self.testProductStyle = targetTriple.isDarwin() ? .loadableBundle : .entryPointExecutable(
            explicitlyEnabledDiscovery: forceTestDiscovery,
            explicitlySpecifiedPath: testEntryPointPath
        )
        self.explicitTargetDependencyImportCheckingMode = explicitTargetDependencyImportCheckingMode
        self.linkerDeadStrip = linkerDeadStrip
        self.colorizedOutput = colorizedOutput
        self.verboseOutput = verboseOutput
        self.linkTimeOptimizationMode = linkTimeOptimizationMode
        self.debugInfoFormat = debugInfoFormat
        self.shouldSkipBuilding = shouldSkipBuilding
        self.experimentalTestOutput = experimentalTestOutput
    }

    @available(*, deprecated, renamed: "forTriple()")
    public func withDestination(_ destinationTriple: Triple) throws -> BuildParameters {
        try self.forTriple(destinationTriple)
    }

    public func forTriple(_ targetTriple: Triple) throws -> BuildParameters {
        let forceTestDiscovery: Bool
        let testEntryPointPath: AbsolutePath?
        switch self.testProductStyle {
        case .entryPointExecutable(let explicitlyEnabledDiscovery, let explicitlySpecifiedPath):
            forceTestDiscovery = explicitlyEnabledDiscovery
            testEntryPointPath = explicitlySpecifiedPath
        case .loadableBundle:
            forceTestDiscovery = false
            testEntryPointPath = nil
        }

        var hostSDK = try SwiftSDK.hostSwiftSDK()
        hostSDK.targetTriple = targetTriple

        return try .init(
            dataPath: self.dataPath.parentDirectory.appending(components: ["plugins", "tools"]),
            configuration: self.configuration,
            toolchain: try UserToolchain(swiftSDK: hostSDK),
            hostTriple: self.hostTriple,
            targetTriple: targetTriple,
            flags: BuildFlags(),
            pkgConfigDirectories: self.pkgConfigDirectories,
            architectures: nil,
            workers: self.workers,
            shouldLinkStaticSwiftStdlib: self.shouldLinkStaticSwiftStdlib,
            shouldDisableLocalRpath: self.shouldDisableLocalRpath,
            shouldEnableManifestCaching: self.shouldEnableManifestCaching,
            canRenameEntrypointFunctionName: self.canRenameEntrypointFunctionName,
            shouldCreateDylibForDynamicProducts: self.shouldCreateDylibForDynamicProducts,
            sanitizers: self.sanitizers,
            enableCodeCoverage: self.enableCodeCoverage,
            indexStoreMode: self.indexStoreMode,
            enableParseableModuleInterfaces: self.enableParseableModuleInterfaces,
            useIntegratedSwiftDriver: self.useIntegratedSwiftDriver,
            useExplicitModuleBuild: self.useExplicitModuleBuild,
            isXcodeBuildSystemEnabled: self.isXcodeBuildSystemEnabled,
            enableTestability: self.enableTestability,
            forceTestDiscovery: forceTestDiscovery,
            testEntryPointPath: testEntryPointPath,
            explicitTargetDependencyImportCheckingMode: self.explicitTargetDependencyImportCheckingMode,
            linkerDeadStrip: self.linkerDeadStrip,
            colorizedOutput: self.colorizedOutput,
            verboseOutput: self.verboseOutput,
            linkTimeOptimizationMode: self.linkTimeOptimizationMode,
            shouldSkipBuilding: self.shouldSkipBuilding
        )
    }

    /// The path to the build directory (inside the data directory).
    public var buildPath: AbsolutePath {
        if isXcodeBuildSystemEnabled {
            return dataPath.appending(components: "Products", configuration.dirname.capitalized)
        } else {
            return dataPath.appending(component: configuration.dirname)
        }
    }

    /// The path to the index store directory.
    public var indexStore: AbsolutePath {
        assert(indexStoreMode != .off, "index store is disabled")
        return buildPath.appending(components: "index", "store")
    }

    /// The path to the code coverage directory.
    public var codeCovPath: AbsolutePath {
        return buildPath.appending("codecov")
    }

    /// The path to the code coverage profdata file.
    public var codeCovDataFile: AbsolutePath {
        return codeCovPath.appending("default.profdata")
    }

    public var llbuildManifest: AbsolutePath {
        return dataPath.appending(components: "..", configuration.dirname + ".yaml")
    }

    public var pifManifest: AbsolutePath {
        return dataPath.appending(components: "..", "manifest.pif")
    }

    public var buildDescriptionPath: AbsolutePath {
        return buildPath.appending(components: "description.json")
    }

    public var testOutputPath: AbsolutePath {
        return buildPath.appending(component: "testOutput.txt")
    }

    /// The debugging strategy according to the current build parameters.
    public var debuggingStrategy: DebuggingStrategy? {
        guard configuration == .debug else {
            return nil
        }

        if targetTriple.isApple() {
            return .swiftAST
        }
        return .modulewrap
    }

    /// Returns the path to the binary of a product for the current build parameters.
    public func binaryPath(for product: ResolvedProduct) throws -> AbsolutePath {
        return try buildPath.appending(binaryRelativePath(for: product))
    }

    /// Returns the path to the dynamic library of a product for the current build parameters.
    func potentialDynamicLibraryPath(for product: ResolvedProduct) throws -> RelativePath {
        try RelativePath(validating: "\(targetTriple.dynamicLibraryPrefix)\(product.name)\(targetTriple.dynamicLibraryExtension)")
    }

    /// Returns the path to the binary of a product for the current build parameters, relative to the build directory.
    public func binaryRelativePath(for product: ResolvedProduct) throws -> RelativePath {
        let potentialExecutablePath = try RelativePath(validating: "\(product.name)\(targetTriple.executableExtension)")

        switch product.type {
        case .executable, .snippet:
            return potentialExecutablePath
        case .library(.static):
            return try RelativePath(validating: "lib\(product.name)\(targetTriple.staticLibraryExtension)")
        case .library(.dynamic):
            return try potentialDynamicLibraryPath(for: product)
        case .library(.automatic), .plugin:
            fatalError()
        case .test:
            guard !targetTriple.isWASI() else {
                return try RelativePath(validating: "\(product.name).wasm")
            }

            let base = "\(product.name).xctest"
            if targetTriple.isDarwin() {
                return try RelativePath(validating: "\(base)/Contents/MacOS/\(product.name)")
            } else {
                return try RelativePath(validating: base)
            }
        case .macro:
            #if BUILD_MACROS_AS_DYLIBS
            return try potentialDynamicLibraryPath(for: product)
            #else
            return potentialExecutablePath
            #endif
        }
    }
}

/// A shim struct for toolchain so we can encode it without having to write encode(to:) for
/// entire BuildParameters by hand.
private struct _Toolchain: Encodable {
    let toolchain: Toolchain

    enum CodingKeys: String, CodingKey {
        case swiftCompiler
        case clangCompiler
        case extraCCFlags
        case extraSwiftCFlags
        case extraCPPFlags
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(toolchain.swiftCompilerPath, forKey: .swiftCompiler)
        try container.encode(toolchain.getClangCompiler(), forKey: .clangCompiler)

        try container.encode(toolchain.extraFlags.cCompilerFlags, forKey: .extraCCFlags)
        // Maintaining `extraCPPFlags` key for compatibility with older encoding.
        try container.encode(toolchain.extraFlags.cxxCompilerFlags, forKey: .extraCPPFlags)
        try container.encode(toolchain.extraFlags.swiftCompilerFlags, forKey: .extraSwiftCFlags)
        try container.encode(toolchain.swiftCompilerPath, forKey: .swiftCompiler)
    }
}

extension BuildParameters {
    /// Whether to build Swift code with whole module optimization (WMO)
    /// enabled.
    public var useWholeModuleOptimization: Bool {
        switch configuration {
        case .debug:
            return false

        case .release:
            return true
        }
    }
}

extension Triple {
    public var supportsTestSummary: Bool {
        return !self.isWindows()
    }
}
