//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
import TSCBasic

import class Basics.AsyncProcess

import struct TSCUtility.Version

/// Errors related to Swift SDKs.
public enum SwiftSDKError: Swift.Error {
    /// A bundle archive should contain at least one directory with the `.artifactbundle` extension.
    case invalidBundleArchive(Basics.AbsolutePath)

    /// A passed argument is neither a valid file system path nor a URL.
    case invalidPathOrURL(String)

    ///  Bundles installed from remote URLs require a checksum to be provided.
    case checksumNotProvided(URL)

    /// Computed archive checksum does not match the provided checksum.
    case checksumInvalid(computed: String, provided: String)

    /// Couldn't find the Xcode installation.
    case invalidInstallation(String)

    /// The schema version is invalid.
    case invalidSchemaVersion

    /// Name of the Swift SDK bundle is not valid.
    case invalidBundleName(String)

    /// No valid Swift SDKs were decoded from a metadata file.
    case noSwiftSDKDecoded(Basics.AbsolutePath)

    /// Path used for storing Swift SDK configuration data is not a directory.
    case pathIsNotDirectory(Basics.AbsolutePath)

    /// Swift SDK metadata couldn't be serialized with the latest serialization schema, potentially because it
    /// was deserialized from an earlier incompatible schema version or initialized manually with properties
    /// required for initialization missing.
    case unserializableMetadata

    /// No configuration values are available for this Swift SDK and target triple.
    case swiftSDKNotFound(artifactID: String, hostTriple: Triple, targetTriple: Triple?)

    /// A Swift SDK bundle with this name is already installed, can't install a new bundle with the same name.
    case swiftSDKBundleAlreadyInstalled(bundleName: String)

    /// A Swift SDK with this artifact ID is already installed. Can't install a new bundle with this artifact,
    /// installed artifact IDs are expected to be unique.
    case swiftSDKArtifactAlreadyInstalled(installedBundleName: String, newBundleName: String, artifactID: String)

    #if os(macOS)
    /// Quarantine attribute should be removed by the `xattr` command from an installed bundle.
    case quarantineAttributePresent(bundlePath: Basics.AbsolutePath)
    #endif
}

extension SwiftSDKError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .checksumInvalid(computed, provided):
            return """
            Computed archive checksum `\(computed)` does not match the provided checksum `\(provided)`.
            """

        case .checksumNotProvided(let url):
            return """
            Bundles installed from remote URLs (`\(url)`) require their checksum passed via `--checksum` option.
            The distributor of the bundle must compute it with the `swift package compute-checksum` \
            command and provide it with their Swift SDK installation instructions.
            """
        case .invalidBundleArchive(let archivePath):
            return """
            Swift SDK archive at `\(archivePath)` does not contain at least one directory with the \
            `.artifactbundle` extension.
            """
        case .invalidPathOrURL(let argument):
            return "`\(argument)` is neither a valid filesystem path nor a URL."
        case .invalidSchemaVersion:
            return "unsupported Swift SDK file schema version"
        case .invalidInstallation(let problem):
            return problem
        case .invalidBundleName(let name):
            return """
            invalid bundle name `\(name)`, unpacked Swift SDK bundles are expected to have `.artifactbundle` extension
            """
        case .noSwiftSDKDecoded(let path):
            return "no valid Swift SDKs were decoded from a metadata file at path `\(path)`"
        case .pathIsNotDirectory(let path):
            return "path expected to be a directory is not a directory or doesn't exist: `\(path)`"
        case .unserializableMetadata:
            return """
            Swift SDK configuration couldn't be serialized with the latest serialization schema, potentially because \
            it was deserialized from an earlier incompatible schema version or initialized manually with missing \
            properties required for initialization
            """
        case .swiftSDKNotFound(let artifactID, let hostTriple, let targetTriple):
            if let targetTriple {
                return """
                Swift SDK with ID `\(artifactID)`, host triple \(hostTriple), and target triple \(targetTriple) is not \
                currently installed.
                """
            } else {
                return """
                Swift SDK with ID `\(artifactID)` is not currently installed.
                """
            }
        case .swiftSDKBundleAlreadyInstalled(let bundleName):
            return """
            Swift SDK bundle with name `\(bundleName)` is already installed. Can't install a new bundle \
            with the same name.
            """
        case .swiftSDKArtifactAlreadyInstalled(let installedBundleName, let newBundleName, let artifactID):
            return """
            A Swift SDK with artifact ID `\(artifactID)` is already included in an installed bundle with name \
            `\(installedBundleName)`. Can't install a new bundle `\(newBundleName)` with this artifact, artifact IDs \
            are expected to be unique across all installed Swift SDK bundles.
            """
        #if os(macOS)
        case .quarantineAttributePresent(let bundlePath):
            return """
            Quarantine attribute is present on a Swift SDK bundle at path `\(bundlePath)`. If you're certain that the \
            bundle was downloaded from a trusted source, you can remove the attribute with this command:

            xattr -d -r -s com.apple.quarantine "\(bundlePath)"

            and try to install this bundle again.
            """
        #endif
        }
    }
}

@available(*, deprecated, renamed: "SwiftSDK")
public typealias Destination = SwiftSDK

/// Swift SDK model type which has information about everything that's required to build a SwiftPM package for a certain
/// platform.
public struct SwiftSDK: Equatable {
    /// The clang/LLVM triple describing the target OS and architecture.
    ///
    /// The triple has the general format <arch><sub>-<vendor>-<sys>-<abi>, where:
    ///  - arch = x86_64, i386, arm, thumb, mips, etc.
    ///  - sub = for ex. on ARM: v5, v6m, v7a, v7m, etc.
    ///  - vendor = pc, apple, nvidia, ibm, etc.
    ///  - sys = none, linux, win32, darwin, cuda, etc.
    ///  - abi = eabi, gnu, android, macho, elf, etc.
    ///
    /// for more information see //https://clang.llvm.org/docs/CrossCompilation.html
    public var targetTriple: Triple?

    /// The clang/LLVM triple describing the host platform that supports this Swift SDK.
    public let hostTriple: Triple?

    // FIXME: this needs to be implemented with either multiple Swift SDKs or making ``SwiftSDK/targetTriple`` an array.
    /// The architectures to build for. We build for host architecture if this is empty.
    public var architectures: [String]? = nil

    /// Whether or not the receiver supports testing.
    @available(*, deprecated, message: "Use `xctestSupport` instead")
    public var supportsTesting: Bool {
        if case .supported = xctestSupport {
            return true
        }
        return false
    }

    /// Whether or not the receiver supports testing using XCTest.
    @_spi(SwiftPMInternal)
    public enum XCTestSupport: Sendable, Equatable {
        /// XCTest is supported.
        case supported

        /// XCTest is not supported.
        ///
        /// - Parameters:
        ///     - reason: A string explaining why XCTest is not supported. If
        ///         `nil`, no additional information is available.
        case unsupported(reason: String?)
    }

    /// Whether or not the receiver supports using XCTest.
    @_spi(SwiftPMInternal)
    public let xctestSupport: XCTestSupport

    /// Root directory path of the SDK used to compile for the target triple.
    @available(*, deprecated, message: "use `pathsConfiguration.sdkRootPath` instead")
    public var sdk: Basics.AbsolutePath? {
        get {
            sdkRootDir
        }
        set {
            sdkRootDir = newValue
        }
    }

    /// Root directory path of the SDK used to compile for the target triple.
    @available(*, deprecated, message: "use `pathsConfiguration.sdkRootPath` instead")
    public var sdkRootDir: Basics.AbsolutePath? {
        get {
            pathsConfiguration.sdkRootPath
        }
        set {
            pathsConfiguration.sdkRootPath = newValue
        }
    }

    /// Path to a directory containing the toolchain (compilers/linker) to be used for the compilation.
    @available(*, deprecated, message: "use `toolset.rootPaths` instead")
    public var binDir: Basics.AbsolutePath {
        toolchainBinDir
    }

    /// Path to a directory containing the toolchain (compilers/linker) to be used for the compilation.
    @available(*, deprecated, message: "use `toolset.rootPaths` instead")
    public var toolchainBinDir: Basics.AbsolutePath {
        toolset.rootPaths[0]
    }

    /// Additional flags to be passed to the C compiler.
    @available(*, deprecated, message: "use `toolset` and its properties instead")
    public var extraCCFlags: [String] {
        extraFlags.cCompilerFlags
    }

    /// Additional flags to be passed to the Swift compiler.
    @available(*, deprecated, message: "use `toolset` and its properties instead")
    public var extraSwiftCFlags: [String] {
        extraFlags.swiftCompilerFlags
    }

    /// Additional flags to be passed to the C++ compiler.
    @available(*, deprecated, message: "use `toolset` and its properties instead")
    public var extraCPPFlags: [String] {
        extraFlags.cxxCompilerFlags
    }

    /// Additional flags to be passed to the build tools.
    @available(*, deprecated, message: "use `toolset` and its properties instead")
    public var extraFlags: BuildFlags {
        .init(
            cCompilerFlags: toolset.knownTools[.cCompiler]?.extraCLIOptions ?? [],
            cxxCompilerFlags: toolset.knownTools[.cxxCompiler]?.extraCLIOptions ?? [],
            swiftCompilerFlags: toolset.knownTools[.swiftCompiler]?.extraCLIOptions ?? [],
            linkerFlags: toolset.knownTools[.linker]?.extraCLIOptions ?? [],
            xcbuildFlags: toolset.knownTools[.xcbuild]?.extraCLIOptions ?? []
        )
    }

    /// Set of tools and their properties used for building code for the target triple. While a serialized Swift SDK
    /// metadata may specify multiple toolset files, these files are consolidated into a single ``Toolset`` value during
    /// deserialization.
    public private(set) var toolset: Toolset

    /// The paths associated with a Swift SDK. The Path type can be a `String`
    /// to encapsulate the arguments for the `SwiftSDKConfigurationStore.configure`
    /// function, or can be a fully-realized `AbsolutePath` when deserialized from a configuration.
    public struct PathsConfiguration<Path: Equatable>: Equatable {
        public init(
            sdkRootPath: Path? = nil,
            swiftResourcesPath: Path? = nil,
            swiftStaticResourcesPath: Path? = nil,
            includeSearchPaths: [Path]? = nil,
            librarySearchPaths: [Path]? = nil,
            toolsetPaths: [Path]? = nil
        ) {
            self.sdkRootPath = sdkRootPath
            self.swiftResourcesPath = swiftResourcesPath
            self.swiftStaticResourcesPath = swiftStaticResourcesPath
            self.includeSearchPaths = includeSearchPaths
            self.librarySearchPaths = librarySearchPaths
            self.toolsetPaths = toolsetPaths
        }

        /// Root directory path of the SDK used to compile for the target triple.
        public var sdkRootPath: Path?

        /// Path containing Swift resources for dynamic linking.
        public var swiftResourcesPath: Path?

        /// Path containing Swift resources for static linking.
        public var swiftStaticResourcesPath: Path?

        /// Array of paths containing headers.
        public var includeSearchPaths: [Path]?

        /// Array of paths containing libraries.
        public var librarySearchPaths: [Path]?

        /// Array of paths containing toolset files.
        public var toolsetPaths: [Path]?

        /// Initialize paths configuration from values deserialized using v3 schema.
        /// - Parameters:
        ///   - properties: properties of the Swift SDK for the given triple.
        ///   - swiftSDKDirectory: directory used for converting relative paths in `properties` to absolute paths.
        fileprivate init(
            _ properties: SerializedDestinationV3.TripleProperties,
            swiftSDKDirectory: Basics.AbsolutePath? = nil
        ) throws where Path == Basics.AbsolutePath {
            self.init(
                sdkRootPath: try AbsolutePath(validating: properties.sdkRootPath, relativeTo: swiftSDKDirectory),
                swiftResourcesPath: try properties.swiftResourcesPath.map {
                    try AbsolutePath(validating: $0, relativeTo: swiftSDKDirectory)
                },
                swiftStaticResourcesPath: try properties.swiftStaticResourcesPath.map {
                    try AbsolutePath(validating: $0, relativeTo: swiftSDKDirectory)
                },
                includeSearchPaths: try properties.includeSearchPaths?.map {
                    try AbsolutePath(validating: $0, relativeTo: swiftSDKDirectory)
                },
                librarySearchPaths: try properties.librarySearchPaths?.map {
                    try AbsolutePath(validating: $0, relativeTo: swiftSDKDirectory)
                },
                toolsetPaths: try properties.toolsetPaths?.map {
                    try AbsolutePath(validating: $0, relativeTo: swiftSDKDirectory)
                }
            )
        }

        /// Initialize paths configuration from values deserialized using v4 schema.
        /// - Parameters:
        ///   - properties: properties of a Swift SDK for the given triple.
        ///   - swiftSDKDirectory: directory used for converting relative paths in `properties` to absolute paths.
        fileprivate init(
            _ properties: SwiftSDKMetadataV4.TripleProperties, 
            swiftSDKDirectory: Basics.AbsolutePath? = nil
        ) throws where Path == Basics.AbsolutePath {
            self.init(
                sdkRootPath: try AbsolutePath(validating: properties.sdkRootPath, relativeTo: swiftSDKDirectory),
                swiftResourcesPath: try properties.swiftResourcesPath.map {
                    try AbsolutePath(validating: $0, relativeTo: swiftSDKDirectory)
                },
                swiftStaticResourcesPath: try properties.swiftStaticResourcesPath.map {
                    try AbsolutePath(validating: $0, relativeTo: swiftSDKDirectory)
                },
                includeSearchPaths: try properties.includeSearchPaths?.map {
                    try AbsolutePath(validating: $0, relativeTo: swiftSDKDirectory)
                },
                librarySearchPaths: try properties.librarySearchPaths?.map {
                    try AbsolutePath(validating: $0, relativeTo: swiftSDKDirectory)
                },
                toolsetPaths: try properties.toolsetPaths?.map {
                    try AbsolutePath(validating: $0, relativeTo: swiftSDKDirectory)
                }
            )
        }

        public mutating func merge(with newConfiguration: Self) {
            if let sdkRootPath = newConfiguration.sdkRootPath {
                self.sdkRootPath = sdkRootPath
            }

            if let swiftResourcesPath = newConfiguration.swiftResourcesPath {
                self.swiftResourcesPath = swiftResourcesPath
            }

            if let swiftStaticResourcesPath = newConfiguration.swiftStaticResourcesPath {
                self.swiftStaticResourcesPath = swiftStaticResourcesPath
            }

            if let includeSearchPaths = newConfiguration.includeSearchPaths {
                self.includeSearchPaths = includeSearchPaths
            }

            if let librarySearchPaths = newConfiguration.librarySearchPaths {
                self.librarySearchPaths = librarySearchPaths
            }

            if let toolsetPaths = newConfiguration.toolsetPaths {
                self.toolsetPaths = toolsetPaths
            }
        }

        mutating func merge(
            with newConfiguration: PathsConfiguration<String>,
            relativeTo basePath: Path?
        ) throws -> [String] where Path == Basics.AbsolutePath {
            var updatedProperties: [String] = []
            if let sdkRootPath = newConfiguration.sdkRootPath {
                self.sdkRootPath = try AbsolutePath(validating: sdkRootPath, relativeTo: basePath)
                updatedProperties.append("sdkRootPath")
            }

            if let swiftResourcesPath = newConfiguration.swiftResourcesPath {
                self.swiftResourcesPath = try AbsolutePath(validating: swiftResourcesPath, relativeTo: basePath)
                updatedProperties.append("swiftResourcesPath")
            }

            if let swiftStaticResourcesPath = newConfiguration.swiftStaticResourcesPath {
                self.swiftResourcesPath = try AbsolutePath(validating: swiftStaticResourcesPath, relativeTo: basePath)
                updatedProperties.append("swiftStaticResourcesPath")
            }

            if let includeSearchPaths = newConfiguration.includeSearchPaths, !includeSearchPaths.isEmpty {
                self.includeSearchPaths = try includeSearchPaths.map { try AbsolutePath(validating: $0, relativeTo: basePath) }
                updatedProperties.append("includeSearchPath")
            }

            if let librarySearchPaths = newConfiguration.librarySearchPaths, !librarySearchPaths.isEmpty {
                self.librarySearchPaths = try librarySearchPaths.map { try AbsolutePath(validating: $0, relativeTo: basePath) }
                updatedProperties.append("librarySearchPath")
            }

            if let toolsetPaths = newConfiguration.toolsetPaths, !toolsetPaths.isEmpty {
                self.toolsetPaths = try toolsetPaths.map { try AbsolutePath(validating: $0, relativeTo: basePath) }
                updatedProperties.append("toolsetPath")
            }

            return updatedProperties
        }
    }

    /// Configuration of file system paths used by this Swift SDK when building.
    public var pathsConfiguration: PathsConfiguration<Basics.AbsolutePath>

    /// Creates a Swift SDK with the specified properties.
    @available(*, deprecated, message: "use `init(targetTriple:sdkRootDir:toolset:)` instead")
    public init(
        target: Triple? = nil,
        sdk: Basics.AbsolutePath?,
        binDir: Basics.AbsolutePath,
        extraCCFlags: [String] = [],
        extraSwiftCFlags: [String] = [],
        extraCPPFlags: [String] = []
    ) {
        self.init(
            targetTriple: target,
            sdkRootDir: sdk,
            toolchainBinDir: binDir,
            extraFlags: BuildFlags(
                cCompilerFlags: extraCCFlags,
                cxxCompilerFlags: extraCPPFlags,
                swiftCompilerFlags: extraSwiftCFlags
            )
        )
    }

    /// Creates a Swift SDK with the specified properties.
    @available(*, deprecated, message: "use `init(hostTriple:targetTriple:toolset:pathsConfiguration:)` instead")
    public init(
        hostTriple: Triple? = nil,
        targetTriple: Triple? = nil,
        sdkRootDir: Basics.AbsolutePath?,
        toolchainBinDir: Basics.AbsolutePath,
        extraFlags: BuildFlags = BuildFlags()
    ) {
        self.init(
            hostTriple: hostTriple,
            targetTriple: targetTriple,
            toolset: Toolset(toolchainBinDir: toolchainBinDir, buildFlags: extraFlags),
            pathsConfiguration: .init(sdkRootPath: sdkRootDir)
        )
    }

    /// Creates a Swift SDK with the specified properties.
    @available(*, deprecated, message: "use `init(hostTriple:targetTriple:toolset:pathsConfiguration:xctestSupport:)` instead")
    public init(
        hostTriple: Triple? = nil,
        targetTriple: Triple? = nil,
        toolset: Toolset,
        pathsConfiguration: PathsConfiguration<Basics.AbsolutePath>,
        supportsTesting: Bool
    ) {
        let xctestSupport: XCTestSupport
        if supportsTesting {
            xctestSupport = .supported
        } else {
            xctestSupport = .unsupported(reason: nil)
        }

        self.init(
            hostTriple: hostTriple,
            targetTriple: targetTriple,
            toolset: toolset,
            pathsConfiguration: pathsConfiguration,
            xctestSupport: xctestSupport
        )
    }

    /// Creates a Swift SDK with the specified properties.
    @_spi(SwiftPMInternal)
    public init(
        hostTriple: Triple? = nil,
        targetTriple: Triple? = nil,
        toolset: Toolset,
        pathsConfiguration: PathsConfiguration<Basics.AbsolutePath>,
        xctestSupport: XCTestSupport = .supported
    ) {
        self.hostTriple = hostTriple
        self.targetTriple = targetTriple
        self.toolset = toolset
        self.pathsConfiguration = pathsConfiguration
        self.xctestSupport = xctestSupport
    }

    /// Returns the bin directory for the host.
    private static func hostBinDir(
        fileSystem: FileSystem
    ) throws -> Basics.AbsolutePath {
        guard let cwd = fileSystem.currentWorkingDirectory else {
            return try AbsolutePath(validating: CommandLine.arguments[0]).parentDirectory
        }
        return try AbsolutePath(validating: CommandLine.arguments[0], relativeTo: cwd).parentDirectory
    }

    /// The Swift SDK describing the host platform.
    @available(*, deprecated, renamed: "hostSwiftSDK")
    public static func hostDestination(
        _ binDir: Basics.AbsolutePath? = nil,
        originalWorkingDirectory: Basics.AbsolutePath? = nil,
        environment: Environment
    ) throws -> SwiftSDK {
        try self.hostSwiftSDK(binDir, environment: environment)
    }

    /// The Swift SDK for the host platform.
    public static func hostSwiftSDK(
        _ binDir: Basics.AbsolutePath? = nil,
        environment: Environment = .current,
        observabilityScope: ObservabilityScope? = nil,
        fileSystem: any FileSystem = Basics.localFileSystem
    ) throws -> SwiftSDK {
        try self.systemSwiftSDK(
            binDir,
            environment: environment,
            observabilityScope: observabilityScope,
            fileSystem: fileSystem
        )
    }

    /// A default Swift SDK on the host.
    ///
    /// Equivalent to `hostSwiftSDK`, except on macOS, where passing a non-nil `darwinPlatformOverride`
    /// will result in the SDK for the corresponding Darwin platform.
    private static func systemSwiftSDK(
        _ binDir: Basics.AbsolutePath? = nil,
        environment: Environment = .current,
        observabilityScope: ObservabilityScope? = nil,
        fileSystem: any FileSystem = Basics.localFileSystem,
        darwinPlatformOverride: DarwinPlatform? = nil
    ) throws -> SwiftSDK {
        // Select the correct binDir.
        if environment["SWIFTPM_CUSTOM_BINDIR"] != nil {
            print("SWIFTPM_CUSTOM_BINDIR was deprecated in favor of SWIFTPM_CUSTOM_BIN_DIR")
        }
        let customBinDir = (environment["SWIFTPM_CUSTOM_BIN_DIR"] ?? environment["SWIFTPM_CUSTOM_BINDIR"])
            .flatMap { try? Basics.AbsolutePath(validating: $0) }
        let binDir = try customBinDir ?? binDir ?? SwiftSDK.hostBinDir(fileSystem: fileSystem)

        let sdkPath: Basics.AbsolutePath?
        #if os(macOS)
        let darwinPlatform = darwinPlatformOverride ?? .macOS
        // Get the SDK.
        if let value = environment["SDKROOT"] {
            sdkPath = try AbsolutePath(validating: value)
        } else if let value = environment[EnvironmentKey("SWIFTPM_SDKROOT_\(darwinPlatform.xcrunName)")] {
            sdkPath = try AbsolutePath(validating: value)
        } else {
            // No value in env, so search for it.
            let sdkPathStr = try AsyncProcess.checkNonZeroExit(
                arguments: ["/usr/bin/xcrun", "--sdk", darwinPlatform.xcrunName, "--show-sdk-path"],
                environment: environment
            ).spm_chomp()
            guard !sdkPathStr.isEmpty else {
                throw SwiftSDKError.invalidInstallation("default SDK not found")
            }
            sdkPath = try AbsolutePath(validating: sdkPathStr)
        }
        #else
        sdkPath = nil
        #endif

        // Compute common arguments for clang and swift.
        let xctestSupport: XCTestSupport
        var extraCCFlags: [String] = []
        var extraSwiftCFlags: [String] = []
        #if os(macOS)
        do {
            let sdkPaths = try SwiftSDK.sdkPlatformPaths(for: darwinPlatform, environment: environment)
            extraCCFlags.append(contentsOf: sdkPaths.frameworks.flatMap { ["-F", $0.pathString] })
            extraSwiftCFlags.append(contentsOf: sdkPaths.frameworks.flatMap { ["-F", $0.pathString] })
            extraSwiftCFlags.append(contentsOf: sdkPaths.libraries.flatMap { ["-I", $0.pathString] })
            extraSwiftCFlags.append(contentsOf: sdkPaths.libraries.flatMap { ["-L", $0.pathString] })
            xctestSupport = .supported
        } catch {
            xctestSupport = .unsupported(reason: String(describing: error))
        }
        #else
        xctestSupport = .supported
        #endif

        #if !os(Windows)
        extraCCFlags += ["-fPIC"]
        #endif

        return SwiftSDK(
            toolset: .init(
                knownTools: [
                    .cCompiler: .init(extraCLIOptions: extraCCFlags),
                    .swiftCompiler: .init(extraCLIOptions: extraSwiftCFlags),
                ],
                rootPaths: [binDir]
            ),
            pathsConfiguration: .init(sdkRootPath: sdkPath),
            xctestSupport: xctestSupport
        )
    }

    /// Auxiliary platform frameworks and libraries.
    ///
    /// The referenced directories may contain, for example, test support utilities.
    ///
    /// - SeeAlso: ``sdkPlatformPaths(for:environment:)``
    public struct PlatformPaths {
        /// Paths of directories containing auxiliary platform frameworks.
        public var frameworks: [Basics.AbsolutePath]

        /// Paths of directories containing auxiliary platform libraries.
        public var libraries: [Basics.AbsolutePath]
    }

    /// Returns `macosx` sdk platform framework path.
    @available(*, deprecated, message: "use sdkPlatformPaths(for:) instead")
    public static func sdkPlatformFrameworkPaths(
        environment: Environment = .current
    ) throws -> (fwk: Basics.AbsolutePath, lib: Basics.AbsolutePath) {
        let paths = try sdkPlatformPaths(for: .macOS, environment: environment)
        guard let frameworkPath = paths.frameworks.first else {
            throw StringError("could not determine SDK platform framework path")
        }
        guard let libraryPath = paths.libraries.first else {
            throw StringError("could not determine SDK platform library path")
        }
        return (fwk: frameworkPath, lib: libraryPath)
    }

    /// Returns ``SwiftSDK/PlatformPaths`` for the provided Darwin platform.
    public static func sdkPlatformPaths(
        for darwinPlatform: DarwinPlatform,
        environment: Environment = .current
    ) throws -> PlatformPaths {
        if let path = _sdkPlatformFrameworkPath[darwinPlatform] {
            return path
        }
        let platformPath = try environment[
            EnvironmentKey("SWIFTPM_PLATFORM_PATH_\(darwinPlatform.xcrunName)")
        ] ?? AsyncProcess.checkNonZeroExit(
            arguments: ["/usr/bin/xcrun", "--sdk", darwinPlatform.xcrunName, "--show-sdk-platform-path"],
            environment: environment
        ).spm_chomp()

        guard !platformPath.isEmpty else {
            throw StringError("could not determine SDK platform path")
        }

        // For testing frameworks.
        let frameworksPath = try Basics.AbsolutePath(validating: platformPath).appending(
            components: "Developer", "Library", "Frameworks"
        )
        let privateFrameworksPath = try Basics.AbsolutePath(validating: platformPath).appending(
            components: "Developer", "Library", "PrivateFrameworks"
        )

        // For testing libraries.
        let librariesPath = try Basics.AbsolutePath(validating: platformPath).appending(
            components: "Developer", "usr", "lib"
        )

        let sdkPlatformFrameworkPath = PlatformPaths(frameworks: [frameworksPath, privateFrameworksPath], libraries: [librariesPath])
        _sdkPlatformFrameworkPath[darwinPlatform] = sdkPlatformFrameworkPath
        return sdkPlatformFrameworkPath
    }

    /// Cache storage for sdk platform paths.
    private static var _sdkPlatformFrameworkPath: [DarwinPlatform: PlatformPaths] = [:]

    /// Returns a default Swift SDK for a given target environment
    @available(*, deprecated, renamed: "defaultSwiftSDK")
    public static func defaultDestination(for triple: Triple, host: SwiftSDK) -> SwiftSDK? {
        defaultSwiftSDK(for: triple, hostSDK: host)
    }

    /// Returns a default Swift SDK of a given target environment.
    public static func defaultSwiftSDK(
        for targetTriple: Triple,
        hostSDK: SwiftSDK,
        environment: Environment = .current
    ) -> SwiftSDK? {
        #if os(macOS)
        if let darwinPlatform = targetTriple.darwinPlatform {
            // the Darwin SDKs are trivially available on macOS
            var sdk = try? self.systemSwiftSDK(
                hostSDK.toolset.rootPaths.first,
                environment: environment,
                darwinPlatformOverride: darwinPlatform
            )
            sdk?.targetTriple = targetTriple
            return sdk
        }
        #endif

        return nil
    }

    /// Computes the target Swift SDK for the given options.
    public static func deriveTargetSwiftSDK(
      hostSwiftSDK: SwiftSDK,
      hostTriple: Triple,
      customToolsets: [Basics.AbsolutePath] = [],
      customCompileDestination: Basics.AbsolutePath? = nil,
      customCompileTriple: Triple? = nil,
      customCompileToolchain: Basics.AbsolutePath? = nil,
      customCompileSDK: Basics.AbsolutePath? = nil,
      swiftSDKSelector: String? = nil,
      architectures: [String] = [],
      store: SwiftSDKBundleStore,
      observabilityScope: ObservabilityScope,
      fileSystem: FileSystem
    ) throws -> SwiftSDK {
        var swiftSDK: SwiftSDK
        var isBasedOnHostSDK: Bool = false

        // Create custom toolchain if present.
        if let customDestination = customCompileDestination {
            let swiftSDKs = try SwiftSDK.decode(
                fromFile: customDestination,
                hostToolchainBinDir: store.hostToolchainBinDir,
                fileSystem: fileSystem,
                observabilityScope: observabilityScope
            )
            if swiftSDKs.count == 1 {
                swiftSDK = swiftSDKs[0]
            } else if swiftSDKs.count > 1,
                      let triple = customCompileTriple,
                      let matchingSDK = swiftSDKs.first(where: { $0.targetTriple == triple })
            {
                swiftSDK = matchingSDK
            } else {
                throw SwiftSDKError.noSwiftSDKDecoded(customDestination)
            }
        } else if let targetTriple = customCompileTriple,
                  let targetSwiftSDK = SwiftSDK.defaultSwiftSDK(for: targetTriple, hostSDK: hostSwiftSDK)
        {
            swiftSDK = targetSwiftSDK
        } else if let swiftSDKSelector {
            do {
                swiftSDK = try store.selectBundle(matching: swiftSDKSelector, hostTriple: hostTriple)
            } catch {
                // If a user-installed bundle for the selector doesn't exist, check if the
                // selector is recognized as a default SDK.
                if let targetTriple = try? Triple(swiftSDKSelector),
                   let defaultSDK = SwiftSDK.defaultSwiftSDK(for: targetTriple, hostSDK: hostSwiftSDK) {
                    swiftSDK = defaultSDK
                } else {
                    throw error
                }
            }
        } else {
            // Otherwise use the host toolchain.
            swiftSDK = hostSwiftSDK
            isBasedOnHostSDK = true
        }

        if !customToolsets.isEmpty {
            for toolsetPath in customToolsets {
                let toolset = try Toolset(from: toolsetPath, at: fileSystem, observabilityScope)
                swiftSDK.toolset.merge(with: toolset)
            }
        }

        // Apply any manual overrides.
        if let triple = customCompileTriple {
            swiftSDK.targetTriple = triple

            if isBasedOnHostSDK && customToolsets.isEmpty {
                // Don't pick up extraCLIOptions for a custom triple, since those are only valid for the host triple.
                for tool in swiftSDK.toolset.knownTools.keys {
                    swiftSDK.toolset.knownTools[tool]?.extraCLIOptions = []
                }
            }
        }

        if let binDir = customCompileToolchain {
            if !fileSystem.exists(binDir) {
                observabilityScope.emit(
                    warning: """
                        Toolchain directory specified through a command-line option doesn't exist and is ignored: `\(
                            binDir
                        )`
                        """
                )
            }

            // `--tooolchain` should override existing anything in the SDK and search paths.
            swiftSDK.prepend(toolsetRootPath: binDir.appending(components: "usr", "bin"))
        }
        if let sdk = customCompileSDK {
            swiftSDK.pathsConfiguration.sdkRootPath = sdk
        }
        swiftSDK.architectures = architectures.isEmpty ? nil : architectures

        if !isBasedOnHostSDK {
            // Append the host toolchain's toolset paths at the end for the case the target Swift SDK
            // doesn't have some of the tools (e.g. swift-frontend might be shared between the host and
            // target Swift SDKs).
            let rootPaths = Set(swiftSDK.toolset.rootPaths)
            for rootPath in hostSwiftSDK.toolset.rootPaths where !rootPaths.contains(rootPath) {
                swiftSDK.append(toolsetRootPath: rootPath)
            }
        }

        return swiftSDK
    }

    /// Propagates toolchain and SDK paths known to the Swift SDK to `swiftc` CLI options.
    public mutating func applyPathCLIOptions() {
        var properties = self.toolset.knownTools[.swiftCompiler] ?? .init(extraCLIOptions: [])
        properties.extraCLIOptions.append(contentsOf: self.toolset.rootPaths.flatMap { ["-tools-directory", $0.pathString] })

        if let sdkDirPath = self.pathsConfiguration.sdkRootPath?.pathString {
            properties.extraCLIOptions.append(contentsOf: ["-sdk", sdkDirPath])
        }

        self.toolset.knownTools[.swiftCompiler] = properties
    }

    /// Prepends a path to the array of toolset root paths.
    ///
    /// Note: Use this operation if you want new root path to take priority over existing paths.
    ///
    /// - Parameter toolsetRootPath: new path to add to Swift SDK's toolset.
    public mutating func prepend(toolsetRootPath path: Basics.AbsolutePath) {
        self.toolset.rootPaths.insert(path, at: 0)
    }

    /// Appends a path to the array of toolset root paths.
    ///
    /// Note: The paths are evaluated in insertion order which means that newly added path would
    /// have a lower priority vs. existing paths.
    ///
    /// - Parameter toolsetRootPath: new path to add to Swift SDK's toolset.
    public mutating func append(toolsetRootPath: Basics.AbsolutePath) {
        self.toolset.rootPaths.append(toolsetRootPath)
    }
}

extension SwiftSDK {
    /// Load a ``SwiftSDK`` description from a JSON representation from disk.
    public static func decode(
        fromFile path: Basics.AbsolutePath,
        hostToolchainBinDir: Basics.AbsolutePath,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope
    ) throws -> [SwiftSDK] {
        let decoder = JSONDecoder.makeWithDefaults()
        do {
            let version = try decoder.decode(path: path, fileSystem: fileSystem, as: SemanticVersionInfo.self)
            return try Self.decode(
                semanticVersion: version,
                fromFile: path,
                hostToolchainBinDir: hostToolchainBinDir,
                fileSystem: fileSystem,
                decoder: decoder,
                observabilityScope: observabilityScope
            )
        } catch DecodingError.keyNotFound {
            let version = try decoder.decode(path: path, fileSystem: fileSystem, as: VersionInfo.self)
            return try [SwiftSDK(legacy: version, fromFile: path, fileSystem: fileSystem, decoder: decoder)]
        }
    }

    /// Load a ``SwiftSDK`` description from a semantically versioned JSON representation from disk.
    private static func decode(
        semanticVersion: SemanticVersionInfo,
        fromFile path: Basics.AbsolutePath,
        hostToolchainBinDir: Basics.AbsolutePath,
        fileSystem: FileSystem,
        decoder: JSONDecoder,
        observabilityScope: ObservabilityScope
    ) throws -> [SwiftSDK] {
        let wasmKitProperties = Toolset.ToolProperties(
            path: hostToolchainBinDir.appending("wasmkit"),
            extraCLIOptions: ["run"]
        )

        switch semanticVersion.schemaVersion {
        case Version(3, 0, 0):
            let swiftSDKs = try decoder.decode(path: path, fileSystem: fileSystem, as: SerializedDestinationV3.self)
            let swiftSDKDirectory = path.parentDirectory

            return try swiftSDKs.runTimeTriples.map { triple, properties in
                let triple = try Triple(triple)

                let pathStrings = properties.toolsetPaths ?? []
                let defaultTools: [Toolset.KnownTool: Toolset.ToolProperties] = if triple.isWasm {
                    [.debugger: wasmKitProperties, .testRunner: wasmKitProperties]
                } else {
                    [:]
                }
                let toolset = try pathStrings.reduce(into: Toolset(knownTools: defaultTools, rootPaths: [])) {
                    try $0.merge(
                        with: Toolset(
                            from: .init(validating: $1, relativeTo: swiftSDKDirectory),
                            at: fileSystem,
                            observabilityScope
                        )
                    )
                }

                return try SwiftSDK(
                    targetTriple: triple,
                    properties: properties,
                    toolset: toolset,
                    swiftSDKDirectory: swiftSDKDirectory
                )
            }

        case Version(4, 0, 0):
            let swiftSDKs = try decoder.decode(path: path, fileSystem: fileSystem, as: SwiftSDKMetadataV4.self)
            let swiftSDKDirectory = path.parentDirectory

            return try swiftSDKs.targetTriples.map { triple, properties in
                let triple = try Triple(triple)

                let defaultTools: [Toolset.KnownTool: Toolset.ToolProperties] = if triple.isWasm {
                    [.debugger: wasmKitProperties, .testRunner: wasmKitProperties]
                } else {
                    [:]
                }
                let pathStrings = properties.toolsetPaths ?? []
                let toolset = try pathStrings.reduce(into: Toolset(knownTools: defaultTools, rootPaths: [])) {
                    try $0.merge(
                        with: Toolset(
                            from: .init(validating: $1, relativeTo: swiftSDKDirectory),
                            at: fileSystem,
                            observabilityScope
                        )
                    )
                }

                return try SwiftSDK(
                    targetTriple: triple,
                    properties: properties,
                    toolset: toolset,
                    swiftSDKDirectory: swiftSDKDirectory
                )
            }
        default:
            throw SwiftSDKError.invalidSchemaVersion
        }
    }

    /// Initialize new Swift SDK from values deserialized using v4 schema.
    /// - Parameters:
    ///   - targetTriple: triple of the machine running code built with this Swift SDK.
    ///   - properties: properties of the Swift SDK for the given triple.
    ///   - toolset: combined toolset used by this Swift SDK.
    ///   - swiftSDKDirectory: directory used for converting relative paths in `properties` to absolute paths.
    init(
        targetTriple: Triple,
        properties: SwiftSDKMetadataV4.TripleProperties,
        toolset: Toolset = .init(),
        swiftSDKDirectory: Basics.AbsolutePath? = nil
    ) throws {
        self.init(
            targetTriple: targetTriple,
            toolset: toolset,
            pathsConfiguration: try .init(properties, swiftSDKDirectory: swiftSDKDirectory)
        )
    }

    /// Initialize new Swift SDK from values deserialized using the v3 schema.
    /// - Parameters:
    ///   - targetTriple: triple of the machine running code built with this Swift SDK.
    ///   - properties: properties of the destination for the given triple.
    ///   - toolset: combined toolset used by this destination.
    ///   - swiftSDKDirectory: directory used for converting relative paths in `properties` to absolute paths.
    private init(
        targetTriple: Triple,
        properties: SerializedDestinationV3.TripleProperties,
        toolset: Toolset = .init(),
        swiftSDKDirectory: Basics.AbsolutePath? = nil
    ) throws {
        self.init(
            targetTriple: targetTriple,
            toolset: toolset,
            pathsConfiguration: try .init(properties, swiftSDKDirectory: swiftSDKDirectory)
        )
    }

    /// Load a ``SwiftSDK`` description from a legacy JSON representation from disk.
    private init(
        legacy version: VersionInfo,
        fromFile path: Basics.AbsolutePath,
        fileSystem: FileSystem,
        decoder: JSONDecoder
    ) throws {
        // Check schema version.
        switch version.version {
        case 1:
            let serializedMetadata = try decoder.decode(
                path: path, 
                fileSystem: fileSystem,
                as: SerializedDestinationV1.self
            )
            try self.init(
                targetTriple: serializedMetadata.target.map { try Triple($0) },
                toolset: .init(
                    toolchainBinDir: serializedMetadata.binDir,
                    buildFlags: .init(
                        cCompilerFlags: serializedMetadata.extraCCFlags,
                        cxxCompilerFlags: serializedMetadata.extraCPPFlags,
                        swiftCompilerFlags: serializedMetadata.extraSwiftCFlags
                    )
                ),
                pathsConfiguration: .init(sdkRootPath: serializedMetadata.sdk)
            )
        case 2:
            let serializedMetadata = try decoder.decode(path: path, fileSystem: fileSystem, as: SerializedDestinationV2.self)
            let swiftSDKDirectory = path.parentDirectory

            try self.init(
                hostTriple: serializedMetadata.hostTriples.map(Triple.init).first,
                targetTriple: serializedMetadata.targetTriples.map(Triple.init).first,
                toolset: .init(
                    toolchainBinDir: AbsolutePath(
                        validating: serializedMetadata.toolchainBinDir,
                        relativeTo: swiftSDKDirectory
                    ),
                    buildFlags: .init(
                        cCompilerFlags: serializedMetadata.extraCCFlags,
                        cxxCompilerFlags: serializedMetadata.extraCXXFlags,
                        swiftCompilerFlags: serializedMetadata.extraSwiftCFlags,
                        linkerFlags: serializedMetadata.extraLinkerFlags
                    )
                ),
                pathsConfiguration: .init(
                    sdkRootPath: AbsolutePath(validating: serializedMetadata.sdkRootDir, relativeTo: swiftSDKDirectory)
                )
            )
        default:
            throw SwiftSDKError.invalidSchemaVersion
        }
    }

    /// Encodes a Swift SDK into its serialized form, which is a pair of its run time triple and paths configuration.
    /// Returns a pair that can be used to reconstruct a `SerializedDestinationV3` value for storage. `nil` if
    /// required configuration properties aren't available on `self`, which can happen if `Swift SDK` was decoded
    /// from different schema versions or constructed manually without providing valid values for such properties.
    var serialized: (Triple, SerializedDestinationV3.TripleProperties) {
        get throws {
            guard let targetTriple = self.targetTriple, let sdkRootDir = self.pathsConfiguration.sdkRootPath else {
                throw SwiftSDKError.unserializableMetadata
            }
            
            return (
                targetTriple,
                .init(
                    sdkRootPath: sdkRootDir.pathString,
                    swiftResourcesPath: self.pathsConfiguration.swiftResourcesPath?.pathString,
                    swiftStaticResourcesPath: self.pathsConfiguration.swiftStaticResourcesPath?.pathString,
                    includeSearchPaths: self.pathsConfiguration.includeSearchPaths?.map(\.pathString),
                    librarySearchPaths: self.pathsConfiguration.librarySearchPaths?.map(\.pathString),
                    toolsetPaths: self.pathsConfiguration.toolsetPaths?.map(\.pathString)
                )
            )
        }
    }
}

extension DarwinPlatform {
    /// The name xcrun uses to identify this platform.
    fileprivate var xcrunName: String {
        switch self {
        case .iOS(.catalyst):
            return "macosx"
        default:
            return platformName
        }
    }
}

/// Integer version of the schema of `destination.json` files used for cross-compilation.
private struct VersionInfo: Codable {
    let version: Int
}

/// Semantic version of the schema of `destination.json` files used for cross-compilation.
private struct SemanticVersionInfo: Decodable {
    let schemaVersion: Version

    enum CodingKeys: String, CodingKey {
        case schemaVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let versionString = try container.decode(String.self, forKey: .schemaVersion)
        self.schemaVersion = try Version(versionString: versionString, usesLenientParsing: true)
    }
}

/// Represents v1 schema of `destination.json` files used for cross-compilation.
private struct SerializedDestinationV1: Codable {
    let target: String?
    let sdk: Basics.AbsolutePath?
    let binDir: Basics.AbsolutePath
    let extraCCFlags: [String]
    let extraSwiftCFlags: [String]
    let extraCPPFlags: [String]

    enum CodingKeys: String, CodingKey {
        case target
        case sdk
        case binDir = "toolchain-bin-dir"
        case extraCCFlags = "extra-cc-flags"
        case extraSwiftCFlags = "extra-swiftc-flags"
        case extraCPPFlags = "extra-cpp-flags"
    }
}

/// Represents v2 schema of `destination.json` files used for cross-compilation.
private struct SerializedDestinationV2: Codable {
    let sdkRootDir: String
    let toolchainBinDir: String
    let hostTriples: [String]
    let targetTriples: [String]
    let extraCCFlags: [String]
    let extraSwiftCFlags: [String]
    let extraCXXFlags: [String]
    let extraLinkerFlags: [String]
}

/// Represents v3 schema of `destination.json` files used for cross-compilation.
struct SerializedDestinationV3: Decodable {
    struct TripleProperties: Codable {
        /// Path relative to `destination.json` containing SDK root.
        var sdkRootPath: String

        /// Path relative to `destination.json` containing Swift resources for dynamic linking.
        var swiftResourcesPath: String?

        /// Path relative to `destination.json` containing Swift resources for static linking.
        var swiftStaticResourcesPath: String?

        /// Array of paths relative to `destination.json` containing headers.
        var includeSearchPaths: [String]?

        /// Array of paths relative to `destination.json` containing libraries.
        var librarySearchPaths: [String]?

        /// Array of paths relative to `destination.json` containing toolset files.
        var toolsetPaths: [String]?
    }

    /// Mapping of triple strings to corresponding properties of such run-time triple.
    let runTimeTriples: [String: TripleProperties]
}

/// Represents v4 schema of `swift-sdk.json` (previously `destination.json`) files used for cross-compilation.
struct SwiftSDKMetadataV4: Decodable {
    struct TripleProperties: Codable {
        /// Path relative to `swift-sdk.json` containing SDK root.
        var sdkRootPath: String

        /// Path relative to `swift-sdk.json` containing Swift resources for dynamic linking.
        var swiftResourcesPath: String?

        /// Path relative to `swift-sdk.json` containing Swift resources for static linking.
        var swiftStaticResourcesPath: String?

        /// Array of paths relative to `swift-sdk.json` containing headers.
        var includeSearchPaths: [String]?

        /// Array of paths relative to `swift-sdk.json` containing libraries.
        var librarySearchPaths: [String]?

        /// Array of paths relative to `swift-sdk.json` containing toolset files.
        var toolsetPaths: [String]?
    }

    /// Mapping of triple strings to corresponding properties of such target triple.
    let targetTriples: [String: TripleProperties]
}

extension Optional where Wrapped == Basics.AbsolutePath {
    fileprivate var configurationString: String {
        self?.pathString ?? "not set"
    }
}

extension Optional where Wrapped == [Basics.AbsolutePath] {
    fileprivate var configurationString: String {
        self?.map(\.pathString).description ?? "not set"
    }
}

extension SwiftSDK.PathsConfiguration: CustomStringConvertible where Path == Basics.AbsolutePath {
    public var description: String {
        """
        sdkRootPath: \(sdkRootPath.configurationString)
        swiftResourcesPath: \(swiftResourcesPath.configurationString)
        swiftStaticResourcesPath: \(swiftStaticResourcesPath.configurationString)
        includeSearchPaths: \(includeSearchPaths.configurationString)
        librarySearchPaths: \(librarySearchPaths.configurationString)
        toolsetPaths: \(toolsetPaths.configurationString)
        """
    }
}

extension Basics.AbsolutePath {
    fileprivate init(validating string: String, relativeTo basePath: Basics.AbsolutePath?) throws {
        if let basePath {
            try self.init(validating: string, relativeTo: basePath)
        } else {
            try self.init(validating: string)
        }
    }
}
