//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
import TSCBasic

import struct TSCUtility.Version

/// Errors related to cross-compilation destinations.
public enum DestinationError: Swift.Error {
    /// A passed argument is neither a valid file system path nor a URL.
    case invalidPathOrURL(String)

    /// Couldn't find the Xcode installation.
    case invalidInstallation(String)

    /// The schema version is invalid.
    case invalidSchemaVersion

    /// Name of the destination bundle is not valid.
    case invalidBundleName(String)

    /// No valid destinations were decoded from a destination file.
    case noDestinationsDecoded(AbsolutePath)

    /// Path used for storing destination configuration data is not a directory.
    case pathIsNotDirectory(AbsolutePath)

    /// A destination couldn't be serialized with the latest serialization schema, potentially because it
    /// was deserialized from an earlier incompatible schema version or initialized manually with properties
    /// required for initialization missing.
    case unserializableDestination

    /// No configuration values are available for this destination and run-time triple.
    case destinationNotFound(artifactID: String, builtTimeTriple: Triple, runTimeTriple: Triple)

    /// A destination bundle with this name is already installed, can't install a new bundle with the same name.
    case destinationBundleAlreadyInstalled(bundleName: String)

    /// A destination with this artifact ID is already installed. Can't install a new bundle with this artifact,
    /// installed artifact IDs are expected to be unique.
    case destinationArtifactAlreadyInstalled(installedBundleName: String, newBundleName: String, artifactID: String)
}

extension DestinationError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidPathOrURL(let argument):
            return "`\(argument)` is neither a valid filesystem path nor a URL."
        case .invalidSchemaVersion:
            return "unsupported destination file schema version"
        case .invalidInstallation(let problem):
            return problem
        case .invalidBundleName(let name):
            return """
            invalid bundle name `\(name)`, unpacked destination bundles are expected to have `.artifactbundle` extension
            """
        case .noDestinationsDecoded(let path):
            return "no valid destinations were decoded from a destination file at path `\(path)`"
        case .pathIsNotDirectory(let path):
            return "path expected to be a directory is not a directory or doesn't exist: `\(path)`"
        case .unserializableDestination:
            return """
            destination couldn't be serialized with the latest serialization schema, potentially because it \
            was deserialized from an earlier incompatible schema version or initialized manually with missing \
            properties required for initialization
            """
        case .destinationNotFound(let artifactID, let buildTimeTriple, let runTimeTriple):
            return """
            destination with ID `\(artifactID)`, build-time triple \(buildTimeTriple), and run-time triple \
            \(runTimeTriple) is not currently installed.
            """
        case .destinationBundleAlreadyInstalled(let bundleName):
            return """
            destination artifact bundle with name `\(bundleName)` is already installed. Can't install a new bundle \
            with the same name.
            """
        case .destinationArtifactAlreadyInstalled(let installedBundleName, let newBundleName, let artifactID):
            return """
            A destination with artifact ID `\(artifactID)` is already included in an installed bundle with name \
            `\(installedBundleName)`. Can't install a new bundle `\(newBundleName)` with this artifact, artifact IDs \
            are expected to be unique across all installed bundles.
            """
        }
    }
}

/// The compilation destination, has information about everything that's required for a certain destination.
public struct Destination: Equatable {
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

    /// The clang/LLVM triple describing the host platform that supports this destination.
    public let hostTriple: Triple?

    // FIXME: this needs to be implemented with either multiple destinations or making ``targetTriple`` an array.
    /// The architectures to build for. We build for host architecture if this is empty.
    public var architectures: [String]? = nil

    /// Root directory path of the SDK used to compile for the destination.
    @available(*, deprecated, message: "use `sdkRootDir` instead")
    public var sdk: AbsolutePath? {
        get {
            sdkRootDir
        }
        set {
            sdkRootDir = newValue
        }
    }

    /// Root directory path of the SDK used to compile for the destination.
    @available(*, deprecated, message: "use `pathsConfiguration.sdkRootPath` instead")
    public var sdkRootDir: AbsolutePath? {
        get {
            pathsConfiguration.sdkRootPath
        }
        set {
            pathsConfiguration.sdkRootPath = newValue
        }
    }

    /// Path to a directory containing the toolchain (compilers/linker) to be used for the compilation.
    @available(*, deprecated, message: "use `toolset.rootPaths` instead")
    public var binDir: AbsolutePath {
        toolchainBinDir
    }

    /// Path to a directory containing the toolchain (compilers/linker) to be used for the compilation.
    @available(*, deprecated, message: "use `toolset.rootPaths` instead")
    public var toolchainBinDir: AbsolutePath {
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

    /// Set of tools and their properties used for building code for this destination. While a serialized destination
    /// may specify multiple toolset files, these files are consolidated into a single ``Toolset`` value during
    /// deserialization.
    public private(set) var toolset: Toolset

    public struct PathsConfiguration: Equatable {
        public init(
            sdkRootPath: AbsolutePath?,
            swiftResourcesPath: AbsolutePath? = nil,
            swiftStaticResourcesPath: AbsolutePath? = nil,
            includeSearchPaths: [AbsolutePath]? = nil,
            librarySearchPaths: [AbsolutePath]? = nil,
            toolsetPaths: [AbsolutePath]? = nil
        ) {
            self.sdkRootPath = sdkRootPath
            self.swiftResourcesPath = swiftResourcesPath
            self.swiftStaticResourcesPath = swiftStaticResourcesPath
            self.includeSearchPaths = includeSearchPaths
            self.librarySearchPaths = librarySearchPaths
            self.toolsetPaths = toolsetPaths
        }

        /// Root directory path of the SDK used to compile for the destination.
        public var sdkRootPath: AbsolutePath?

        /// Path containing Swift resources for dynamic linking.
        public var swiftResourcesPath: AbsolutePath?

        /// Path containing Swift resources for static linking.
        public var swiftStaticResourcesPath: AbsolutePath?

        /// Array of paths containing headers.
        public var includeSearchPaths: [AbsolutePath]?

        /// Array of paths containing libraries.
        public var librarySearchPaths: [AbsolutePath]?

        /// Array of paths containing toolset files.
        public var toolsetPaths: [AbsolutePath]?

        /// Initialize paths configuration from values deserialized using v3 schema.
        /// - Parameters:
        ///   - properties: properties of the destination for the given triple.
        ///   - destinationDirectory: directory used for converting relative paths in `properties` to absolute paths.
        init(_ properties: SerializedDestinationV3.TripleProperties, destinationDirectory: AbsolutePath? = nil) throws {
            if let destinationDirectory {
                self.init(
                    sdkRootPath: try AbsolutePath(validating: properties.sdkRootPath, relativeTo: destinationDirectory),
                    swiftResourcesPath: try properties.swiftResourcesPath.map {
                        try AbsolutePath(validating: $0, relativeTo: destinationDirectory)
                    },
                    swiftStaticResourcesPath: try properties.swiftStaticResourcesPath.map {
                        try AbsolutePath(validating: $0, relativeTo: destinationDirectory)
                    },
                    includeSearchPaths: try properties.includeSearchPaths?.map {
                        try AbsolutePath(validating: $0, relativeTo: destinationDirectory)
                    },
                    librarySearchPaths: try properties.librarySearchPaths?.map {
                        try AbsolutePath(validating: $0, relativeTo: destinationDirectory)
                    },
                    toolsetPaths: try properties.toolsetPaths?.map {
                        try AbsolutePath(validating: $0, relativeTo: destinationDirectory)
                    }
                )
            } else {
                self.init(
                    sdkRootPath: try AbsolutePath(validating: properties.sdkRootPath),
                    swiftResourcesPath: try properties.swiftResourcesPath.map {
                        try AbsolutePath(validating: $0)
                    },
                    swiftStaticResourcesPath: try properties.swiftStaticResourcesPath.map {
                        try AbsolutePath(validating: $0)
                    },
                    includeSearchPaths: try properties.includeSearchPaths?.map {
                        try AbsolutePath(validating: $0)
                    },
                    librarySearchPaths: try properties.librarySearchPaths?.map {
                        try AbsolutePath(validating: $0)
                    },
                    toolsetPaths: try properties.toolsetPaths?.map {
                        try AbsolutePath(validating: $0)
                    }
                )
            }
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
    }

    /// Configuration of file system paths used by this destination when building.
    public var pathsConfiguration: PathsConfiguration

    /// Creates a compilation destination with the specified properties.
    @available(*, deprecated, message: "use `init(targetTriple:sdkRootDir:toolset:)` instead")
    public init(
        target: Triple? = nil,
        sdk: AbsolutePath?,
        binDir: AbsolutePath,
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

    /// Creates a compilation destination with the specified properties.
    @available(*, deprecated, message: "use `init(hostTriple:targetTriple:toolset:pathsConfiguration:)` instead")
    public init(
        hostTriple: Triple? = nil,
        targetTriple: Triple? = nil,
        sdkRootDir: AbsolutePath?,
        toolchainBinDir: AbsolutePath,
        extraFlags: BuildFlags = BuildFlags()
    ) {
        self.init(
            hostTriple: hostTriple,
            targetTriple: targetTriple,
            toolset: Toolset(toolchainBinDir: toolchainBinDir, buildFlags: extraFlags),
            pathsConfiguration: .init(sdkRootPath: sdkRootDir)
        )
    }

    /// Creates a compilation destination with the specified properties.
    public init(
        hostTriple: Triple? = nil,
        targetTriple: Triple? = nil,
        toolset: Toolset,
        pathsConfiguration: PathsConfiguration
    ) {
        self.hostTriple = hostTriple
        self.targetTriple = targetTriple
        self.toolset = toolset
        self.pathsConfiguration = pathsConfiguration
    }

    /// Returns the bin directory for the host.
    ///
    /// - Parameter originalWorkingDirectory: The working directory when the program was launched.
    private static func hostBinDir(
        fileSystem: FileSystem,
        originalWorkingDirectory: AbsolutePath? = nil
    ) throws -> AbsolutePath {
        let originalWorkingDirectory = originalWorkingDirectory ?? fileSystem.currentWorkingDirectory
        guard let cwd = originalWorkingDirectory else {
            return try AbsolutePath(validating: CommandLine.arguments[0]).parentDirectory
        }
        return try AbsolutePath(validating: CommandLine.arguments[0], relativeTo: cwd).parentDirectory
    }

    /// The destination describing the host OS.
    public static func hostDestination(
        _ binDir: AbsolutePath? = nil,
        originalWorkingDirectory: AbsolutePath? = nil,
        environment: [String: String] = ProcessEnv.vars
    ) throws -> Destination {
        let originalWorkingDirectory = originalWorkingDirectory ?? localFileSystem.currentWorkingDirectory
        // Select the correct binDir.
        if ProcessEnv.vars["SWIFTPM_CUSTOM_BINDIR"] != nil {
            print("SWIFTPM_CUSTOM_BINDIR was deprecated in favor of SWIFTPM_CUSTOM_BIN_DIR")
        }
        let customBinDir = (ProcessEnv.vars["SWIFTPM_CUSTOM_BIN_DIR"] ?? ProcessEnv.vars["SWIFTPM_CUSTOM_BINDIR"])
            .flatMap { try? AbsolutePath(validating: $0) }
        let binDir = try customBinDir ?? binDir ?? Destination.hostBinDir(
            fileSystem: localFileSystem,
            originalWorkingDirectory: originalWorkingDirectory
        )

        let sdkPath: AbsolutePath?
        #if os(macOS)
        // Get the SDK.
        if let value = lookupExecutablePath(filename: ProcessEnv.vars["SDKROOT"]) {
            sdkPath = value
        } else {
            // No value in env, so search for it.
            let sdkPathStr = try TSCBasic.Process.checkNonZeroExit(
                arguments: ["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-path"],
                environment: environment
            ).spm_chomp()
            guard !sdkPathStr.isEmpty else {
                throw DestinationError.invalidInstallation("default SDK not found")
            }
            sdkPath = try AbsolutePath(validating: sdkPathStr)
        }
        #else
        sdkPath = nil
        #endif

        // Compute common arguments for clang and swift.
        var extraCCFlags: [String] = []
        var extraSwiftCFlags: [String] = []
        #if os(macOS)
        let sdkPaths = try Destination.sdkPlatformFrameworkPaths(environment: environment)
        extraCCFlags += ["-F", sdkPaths.fwk.pathString]
        extraSwiftCFlags += ["-F", sdkPaths.fwk.pathString]
        extraSwiftCFlags += ["-I", sdkPaths.lib.pathString]
        extraSwiftCFlags += ["-L", sdkPaths.lib.pathString]
        #endif

        #if !os(Windows)
        extraCCFlags += ["-fPIC"]
        #endif

        return Destination(
            toolset: .init(
                knownTools: [
                    .cCompiler: .init(extraCLIOptions: extraCCFlags),
                    .swiftCompiler: .init(extraCLIOptions: extraSwiftCFlags),
                ],
                rootPaths: [binDir]
            ),
            pathsConfiguration: .init(sdkRootPath: sdkPath)
        )
    }

    /// Returns `macosx` sdk platform framework path.
    public static func sdkPlatformFrameworkPaths(
        environment: EnvironmentVariables = .process()
    ) throws -> (fwk: AbsolutePath, lib: AbsolutePath) {
        if let path = _sdkPlatformFrameworkPath {
            return path
        }
        let platformPath = try TSCBasic.Process.checkNonZeroExit(
            arguments: ["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-platform-path"],
            environment: environment
        ).spm_chomp()

        guard !platformPath.isEmpty else {
            throw StringError("could not determine SDK platform path")
        }

        // For XCTest framework.
        let fwk = try AbsolutePath(validating: platformPath).appending(
            components: "Developer", "Library", "Frameworks"
        )

        // For XCTest Swift library.
        let lib = try AbsolutePath(validating: platformPath).appending(
            components: "Developer", "usr", "lib"
        )

        let sdkPlatformFrameworkPath = (fwk, lib)
        _sdkPlatformFrameworkPath = sdkPlatformFrameworkPath
        return sdkPlatformFrameworkPath
    }

    // FIXME: convert this from a tuple to a proper struct with documented properties
    /// Cache storage for sdk platform path.
    private static var _sdkPlatformFrameworkPath: (fwk: AbsolutePath, lib: AbsolutePath)? = nil

    /// Returns a default destination of a given target environment
    public static func defaultDestination(for triple: Triple, host: Destination) -> Destination? {
        if triple.isWASI() {
            let wasiSysroot = host.toolset.rootPaths.first?
                .parentDirectory // usr
                .appending(components: "share", "wasi-sysroot")
            return Destination(
                targetTriple: triple,
                toolset: host.toolset,
                pathsConfiguration: .init(sdkRootPath: wasiSysroot)
            )
        }
        return nil
    }

    /// Propagates toolchain and SDK paths known to the destination to `swiftc` CLI options.
    public mutating func applyPathCLIOptions() {
        var properties = self.toolset.knownTools[.swiftCompiler] ?? .init(extraCLIOptions: [])
        properties.extraCLIOptions.append(contentsOf: self.toolset.rootPaths.flatMap { ["-tools-directory", $0.pathString] })

        if let sdkDirPath = self.pathsConfiguration.sdkRootPath?.pathString {
            properties.extraCLIOptions.append(contentsOf: ["-sdk", sdkDirPath])
        }

        self.toolset.knownTools[.swiftCompiler] = properties
    }

    /// Appends a path to the array of toolset root paths.
    /// - Parameter toolsetRootPath: new path to add to the destination's toolset.
    public mutating func add(toolsetRootPath: AbsolutePath) {
        self.toolset.rootPaths.append(toolsetRootPath)
    }
}

extension Destination {
    /// Load a ``Destination`` description from a JSON representation from disk.
    public static func decode(
        fromFile path: AbsolutePath,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope
    ) throws -> [Destination] {
        let decoder = JSONDecoder.makeWithDefaults()
        do {
            let version = try decoder.decode(path: path, fileSystem: fileSystem, as: SemanticVersionInfo.self)
            return try Self.decode(
                semanticVersion: version,
                fromFile: path,
                fileSystem: fileSystem,
                decoder: decoder,
                observabilityScope: observabilityScope
            )
        } catch DecodingError.keyNotFound {
            let version = try decoder.decode(path: path, fileSystem: fileSystem, as: VersionInfo.self)
            return try [Destination(legacy: version, fromFile: path, fileSystem: fileSystem, decoder: decoder)]
        }
    }

    /// Load a ``Destination`` description from a semantically versioned JSON representation from disk.
    private static func decode(
        semanticVersion: SemanticVersionInfo,
        fromFile path: AbsolutePath,
        fileSystem: FileSystem,
        decoder: JSONDecoder,
        observabilityScope: ObservabilityScope
    ) throws -> [Destination] {
        switch semanticVersion.schemaVersion {
        case Version(3, 0, 0):
            let destinations = try decoder.decode(path: path, fileSystem: fileSystem, as: SerializedDestinationV3.self)
            let destinationDirectory = path.parentDirectory

            return try destinations.runTimeTriples.map { triple, properties in
                let triple = try Triple(triple)

                let pathStrings = properties.toolsetPaths ?? []
                let toolset = try pathStrings.reduce(into: Toolset(knownTools: [:], rootPaths: [])) {
                    try $0.merge(
                        with: Toolset(
                            from: .init(validating: $1, relativeTo: destinationDirectory),
                            at: fileSystem,
                            observabilityScope
                        )
                    )
                }

                return try Destination(
                    runTimeTriple: triple,
                    properties: properties,
                    toolset: toolset,
                    destinationDirectory: destinationDirectory
                )
            }
        default:
            throw DestinationError.invalidSchemaVersion
        }
    }

    
    /// Initialize new destination from values deserialized using v3 schema.
    /// - Parameters:
    ///   - runTimeTriple: triple of the machine running code built with this destination.
    ///   - properties: properties of the destination for the given triple.
    ///   - toolset: combined toolset used by this destination.
    ///   - destinationDirectory: directory used for converting relative paths in `properties` to absolute paths.
    init(
        runTimeTriple: Triple,
        properties: SerializedDestinationV3.TripleProperties,
        toolset: Toolset = .init(),
        destinationDirectory: AbsolutePath? = nil
    ) throws {
        self.init(
            targetTriple: runTimeTriple,
            toolset: toolset,
            pathsConfiguration: try .init(properties, destinationDirectory: destinationDirectory)
        )
    }

    /// Load a ``Destination`` description from a legacy JSON representation from disk.
    private init(
        legacy version: VersionInfo,
        fromFile path: AbsolutePath,
        fileSystem: FileSystem,
        decoder: JSONDecoder
    ) throws {
        // Check schema version.
        switch version.version {
        case 1:
            let destination = try decoder.decode(path: path, fileSystem: fileSystem, as: SerializedDestinationV1.self)
            try self.init(
                targetTriple: destination.target.map { try Triple($0) },
                toolset: .init(
                    toolchainBinDir: destination.binDir,
                    buildFlags: .init(
                        cCompilerFlags: destination.extraCCFlags,
                        cxxCompilerFlags: destination.extraCPPFlags,
                        swiftCompilerFlags: destination.extraSwiftCFlags
                    )
                ),
                pathsConfiguration: .init(sdkRootPath: destination.sdk)
            )
        case 2:
            let destination = try decoder.decode(path: path, fileSystem: fileSystem, as: SerializedDestinationV2.self)
            let destinationDirectory = path.parentDirectory

            try self.init(
                hostTriple: destination.hostTriples.map(Triple.init).first,
                targetTriple: destination.targetTriples.map(Triple.init).first,
                toolset: .init(
                    toolchainBinDir: AbsolutePath(
                        validating: destination.toolchainBinDir,
                        relativeTo: destinationDirectory
                    ),
                    buildFlags: .init(
                        cCompilerFlags: destination.extraCCFlags,
                        cxxCompilerFlags: destination.extraCXXFlags,
                        swiftCompilerFlags: destination.extraSwiftCFlags,
                        linkerFlags: destination.extraLinkerFlags
                    )
                ),
                pathsConfiguration: .init(
                    sdkRootPath: AbsolutePath(validating: destination.sdkRootDir, relativeTo: destinationDirectory)
                )
            )
        default:
            throw DestinationError.invalidSchemaVersion
        }
    }

    /// Encodes a destination into its serialized form, which is a pair of its run time triple and paths configuration.
    /// Returns a pair that can be used to reconstruct a `SerializedDestinationV3` value for storage. `nil` if
    /// required configuration properties aren't available on `self`, which can happen if `Destination` was decoded
    /// from different schema versions or constructed manually without providing valid values for such properties.
    var serialized: (Triple, SerializedDestinationV3.TripleProperties) {
        get throws {
            guard let runTimeTriple = self.targetTriple, let sdkRootDir = self.pathsConfiguration.sdkRootPath else {
                throw DestinationError.unserializableDestination
            }
            
            return (
                runTimeTriple,
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
    let sdk: AbsolutePath?
    let binDir: AbsolutePath
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
