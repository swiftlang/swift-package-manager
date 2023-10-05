//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020-2023 Apple Inc. and the Swift project authors
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
    @available(*, deprecated, renamed: "LinkingParameters.LinkTimeOptimizationMode")
    public typealias LinkTimeOptimizationMode = LinkingParameters.LinkTimeOptimizationMode
    
    @available(*, deprecated, renamed: "TestingParameters.TestProductStyle")
    public typealias TestProductStyle = TestingParameters.TestProductStyle

    /// Mode for the indexing-while-building feature.
    public enum IndexStoreMode: String, Encodable {
        /// Index store should be enabled.
        case on
        /// Index store should be disabled.
        case off
        /// Index store should be enabled in debug configuration.
        case auto
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
    // FIXME: this may be inconsistent with `targetTriple`.
    public var architectures: [String]?

    /// How many jobs should llbuild and the Swift compiler spawn
    public var workers: UInt32

    /// If should link the Swift stdlib statically.
    @available(*, deprecated, renamed: "linkingParameters.shouldLinkStaticSwiftStdlib")
    public var shouldLinkStaticSwiftStdlib: Bool {
        get {
            linkingParameters.shouldLinkStaticSwiftStdlib
        }
        set {
            linkingParameters.shouldLinkStaticSwiftStdlib = newValue
        }
    }

    /// Which compiler sanitizers should be enabled
    public var sanitizers: EnabledSanitizers

    /// If should enable llbuild manifest caching.
    public var shouldEnableManifestCaching: Bool

    /// The mode to use for indexing-while-building feature.
    public var indexStoreMode: IndexStoreMode

    /// Whether to enable code coverage.
    @available(*, deprecated, renamed: "testingParameters.enableCodeCoverage")
    public var enableCodeCoverage: Bool {
        get {
            testingParameters.enableCodeCoverage
        }
        set {
            testingParameters.enableCodeCoverage = newValue
        }
    }

    /// Whether to enable generation of `.swiftinterface` files alongside.
    /// `.swiftmodule`s.
    public var enableParseableModuleInterfaces: Bool

    /// Whether to use the integrated Swift driver rather than shelling out
    /// to a separate process.
    @available(*, deprecated, renamed: "driverParameters.useIntegratedSwiftDriver")
    public var useIntegratedSwiftDriver: Bool {
        get {
            driverParameters.useIntegratedSwiftDriver
        }
        set {
            driverParameters.useIntegratedSwiftDriver = newValue
        }
    }

    /// Whether to use the explicit module build flow (with the integrated driver).
    @available(*, deprecated, renamed: "driverParameters.useExplicitModuleBuild")
    public var useExplicitModuleBuild: Bool {
        get {
            driverParameters.useExplicitModuleBuild
        }
        set {
            driverParameters.useExplicitModuleBuild = newValue
        }
    }

    /// A flag that indicates this build should check whether targets only import.
    /// their explicitly-declared dependencies
    public var explicitTargetDependencyImportCheckingMode: TargetDependencyImportCheckingMode

    /// Whether to create dylibs for dynamic library products.
    public var shouldCreateDylibForDynamicProducts: Bool

    /// Whether to enable the entry-point-function-name feature.
    public var canRenameEntrypointFunctionName: Bool

    /// Whether or not to enable the experimental test output mode.
    @available(*, deprecated, renamed: "testingParameters.experimentalTestOutput")
    public var experimentalTestOutput: Bool {
        get {
            testingParameters.experimentalTestOutput
        }
        set {
            testingParameters.experimentalTestOutput = newValue
        }
    }


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
    @available(*, deprecated, renamed: "testingParameters.enableTestability")
    public var enableTestability: Bool {
        get {
            testingParameters.enableTestability
        }
        set {
            testingParameters.enableTestability = newValue
        }
    }

    /// The style of test product to produce.
    @available(*, deprecated, renamed: "testingParameters.testProductStyle")
    public var testProductStyle: TestProductStyle {
        get {
            testingParameters.testProductStyle
        }
        set {
            testingParameters.testProductStyle = newValue
        }
    }


    /// Whether to disable dead code stripping by the linker
    @available(*, deprecated, renamed: "linkingParameters.linkerDeadStrip")
    public var linkerDeadStrip: Bool {
        get {
            linkingParameters.linkerDeadStrip
        }
        set {
            linkingParameters.linkerDeadStrip = newValue
        }
    }


    public var colorizedOutput: Bool

    public var verboseOutput: Bool

    public var debugInfoFormat: DebugInfoFormat

    public var shouldSkipBuilding: Bool

    /// Build parameters related to Swift Driver.
    public var driverParameters: DriverParameters

    /// Build parameters related to linking.
    public var testingParameters: TestingParameters

    /// Build parameters related to linking.
    public var linkingParameters: LinkingParameters

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

    @available(*, deprecated, message: "use `init` overload with `linkingParameters` and `testingParameters` parameter names instead")
    @_disfavoredOverload
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
        shouldEnableManifestCaching: Bool = false,
        canRenameEntrypointFunctionName: Bool = false,
        shouldCreateDylibForDynamicProducts: Bool = true,
        sanitizers: EnabledSanitizers = EnabledSanitizers(),
        indexStoreMode: IndexStoreMode = .auto,
        enableParseableModuleInterfaces: Bool = false,
        useIntegratedSwiftDriver: Bool = false,
        useExplicitModuleBuild: Bool = false,
        isXcodeBuildSystemEnabled: Bool = false,
        enableTestability: Bool? = nil,
        forceTestDiscovery: Bool = false,
        testEntryPointPath: AbsolutePath? = nil,
        explicitTargetDependencyImportCheckingMode: TargetDependencyImportCheckingMode = .none,
        colorizedOutput: Bool = false,
        verboseOutput: Bool = false,
        debugInfoFormat: DebugInfoFormat = .dwarf,
        shouldSkipBuilding: Bool = false,
        testingParameters: TestingParameters? = nil,
        linkingParameters: LinkingParameters = .init()
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
        self.shouldEnableManifestCaching = shouldEnableManifestCaching
        self.shouldCreateDylibForDynamicProducts = shouldCreateDylibForDynamicProducts
        self.canRenameEntrypointFunctionName = canRenameEntrypointFunctionName
        self.sanitizers = sanitizers
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
        self.explicitTargetDependencyImportCheckingMode = explicitTargetDependencyImportCheckingMode
        self.colorizedOutput = colorizedOutput
        self.verboseOutput = verboseOutput
        self.debugInfoFormat = debugInfoFormat
        self.shouldSkipBuilding = shouldSkipBuilding
        if let testingParameters {
            self.testingParameters = testingParameters
        } else {
            self.testingParameters = .init(
                testProductStyle: targetTriple.isDarwin() ? .loadableBundle : .entryPointExecutable(
                    explicitlyEnabledDiscovery: forceTestDiscovery,
                    explicitlySpecifiedPath: testEntryPointPath
                ),
                enableTestability: enableTestability ?? (.debug == configuration)
            )
        }
        self.linkingParameters = linkingParameters
    }

    @available(*, deprecated, renamed: "forTriple()")
    public func withDestination(_ destinationTriple: Triple) throws -> BuildParameters {
        try self.forTriple(destinationTriple)
    }

    public func forTriple(_ targetTriple: Triple) throws -> BuildParameters {
        let forceTestDiscovery: Bool
        let testEntryPointPath: AbsolutePath?
        switch self.testingParameters.testProductStyle {
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
            shouldEnableManifestCaching: self.shouldEnableManifestCaching,
            canRenameEntrypointFunctionName: self.canRenameEntrypointFunctionName,
            shouldCreateDylibForDynamicProducts: self.shouldCreateDylibForDynamicProducts,
            sanitizers: self.sanitizers,
            indexStoreMode: self.indexStoreMode,
            enableParseableModuleInterfaces: self.enableParseableModuleInterfaces,
            useIntegratedSwiftDriver: self.useIntegratedSwiftDriver,
            useExplicitModuleBuild: self.useExplicitModuleBuild,
            isXcodeBuildSystemEnabled: self.isXcodeBuildSystemEnabled,
            forceTestDiscovery: forceTestDiscovery,
            testEntryPointPath: testEntryPointPath,
            explicitTargetDependencyImportCheckingMode: self.explicitTargetDependencyImportCheckingMode,
            colorizedOutput: self.colorizedOutput,
            verboseOutput: self.verboseOutput,
            shouldSkipBuilding: self.shouldSkipBuilding,
            testingParameters: self.testingParameters,
            linkingParameters: self.linkingParameters
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
