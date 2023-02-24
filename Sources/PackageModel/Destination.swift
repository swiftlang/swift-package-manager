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

import struct TSCUtility.Triple
import struct TSCUtility.Version

public enum DestinationError: Swift.Error {
    /// Couldn't find the Xcode installation.
    case invalidInstallation(String)

    /// The schema version is invalid.
    case invalidSchemaVersion

    /// No valid destinations were decoded from a destination file.
    case noDestinationsDecoded(AbsolutePath)
}

extension DestinationError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidSchemaVersion:
            return "unsupported destination file schema version"
        case .invalidInstallation(let problem):
            return problem
        case .noDestinationsDecoded(let path):
            return "no valid destinations were decoded from a destination file at path `\(path)`"
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
    public var sdkRootDir: AbsolutePath?

    /// Path to a directory containing the toolchain (compilers/linker) to be used for the compilation.
    @available(*, deprecated, message: "use `toolchainBinDir` instead")
    public var binDir: AbsolutePath {
        toolchainBinDir
    }

    /// Path to a directory containing the toolchain (compilers/linker) to be used for the compilation.
    @available(*, deprecated, message: "use `toolset.rootPaths` instead")
    public var toolchainBinDir: AbsolutePath {
        toolset.rootPaths[0]
    }

    /// Additional flags to be passed to the C compiler.
    @available(*, deprecated, message: "use `extraFlags.cCompilerFlags` instead")
    public var extraCCFlags: [String] {
        extraFlags.cCompilerFlags
    }

    /// Additional flags to be passed to the Swift compiler.
    @available(*, deprecated, message: "use `extraFlags.swiftCompilerFlags` instead")
    public var extraSwiftCFlags: [String] {
        extraFlags.swiftCompilerFlags
    }

    /// Additional flags to be passed to the C++ compiler.
    @available(*, deprecated, message: "use `extraFlags.cxxCompilerFlags` instead")
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
    @available(*, deprecated, message: "use `init(hostTriple:targetTriple:sdkRootDir:toolset:)` instead")
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
            sdkRootDir: sdkRootDir,
            toolset: Toolset(toolchainBinDir: toolchainBinDir, buildFlags: extraFlags)
        )
    }

    /// Creates a compilation destination with the specified properties.
    public init(
        hostTriple: Triple? = nil,
        targetTriple: Triple? = nil,
        sdkRootDir: AbsolutePath?,
        toolset: Toolset
    ) {
        self.hostTriple = hostTriple
        self.targetTriple = targetTriple
        self.sdkRootDir = sdkRootDir
        self.toolset = toolset
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
            sdkRootDir: sdkPath,
            toolset: .init(
                knownTools: [
                    .cCompiler: .init(extraCLIOptions: extraCCFlags),
                    .swiftCompiler: .init(extraCLIOptions: extraSwiftCFlags),
                ],
                rootPaths: [binDir]
            )
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
                sdkRootDir: wasiSysroot,
                toolset: host.toolset
            )
        }
        return nil
    }

    /// Propagates toolchain and SDK paths known to the destination to `swiftc` CLI options.
    public mutating func applyPathCLIOptions() {
        var properties = toolset.knownTools[.swiftCompiler] ?? .init(extraCLIOptions: [])
        properties.extraCLIOptions.append(contentsOf: toolset.rootPaths.flatMap { ["-tools-directory", $0.pathString] })

        if let sdkDirPath = sdkRootDir?.pathString {
            properties.extraCLIOptions.append(contentsOf: ["-sdk", sdkDirPath])
        }

        toolset.knownTools[.swiftCompiler] = properties
    }

    /// Appends a path to the array of toolset root paths.
    /// - Parameter toolsetRootPath: new path to add to the destination's toolset.
    public mutating func add(toolsetRootPath: AbsolutePath) {
        toolset.rootPaths.append(toolsetRootPath)
    }
}

extension Destination {
    /// Load a ``Destination`` description from a JSON representation from disk.
    public static func decode(
        fromFile path: AbsolutePath,
        fileSystem: FileSystem,
        observability: ObservabilityScope
    ) throws -> [Destination] {
        let decoder = JSONDecoder.makeWithDefaults()
        do {
            let version = try decoder.decode(path: path, fileSystem: fileSystem, as: SemanticVersionInfo.self)
            return try Self.decode(semanticVersion: version, fromFile: path, fileSystem: fileSystem, decoder: decoder, observability: observability)
        } catch {
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
        observability: ObservabilityScope
    ) throws -> [Destination] {
        switch semanticVersion.schemaVersion {
        case Version(3, 0, 0):
            let destinations = try decoder.decode(path: path, fileSystem: fileSystem, as: DecodedDestinationV3.self)
            let destinationDirectory = path.parentDirectory

            return try destinations.runTimeTriples.map { triple, properties in
                let triple = try Triple(triple)

                let pathStrings = properties.toolsetPaths ?? []
                let toolset = try pathStrings.reduce(into: Toolset(knownTools: [:], rootPaths: [])) {
                    try $0.merge(with: .init(from: .init(validating: $1, relativeTo: destinationDirectory), at: fileSystem, observability))
                }

                return Destination(
                    targetTriple: triple,
                    sdkRootDir: try .init(validating: properties.sdkRootPath, relativeTo: destinationDirectory),
                    toolset: toolset
                )
            }
        default:
            throw DestinationError.invalidSchemaVersion
        }
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
            let destination = try decoder.decode(path: path, fileSystem: fileSystem, as: DecodedDestinationV1.self)
            try self.init(
                targetTriple: destination.target.map { try Triple($0) },
                sdkRootDir: destination.sdk,
                toolset: .init(
                    toolchainBinDir: destination.binDir,
                    buildFlags: .init(
                        cCompilerFlags: destination.extraCCFlags,
                        cxxCompilerFlags: destination.extraCPPFlags,
                        swiftCompilerFlags: destination.extraSwiftCFlags
                    )
                )
            )
        case 2:
            let destination = try decoder.decode(path: path, fileSystem: fileSystem, as: DecodedDestinationV2.self)
            let destinationDirectory = path.parentDirectory

            try self.init(
                hostTriple: destination.hostTriples.map(Triple.init).first,
                targetTriple: destination.targetTriples.map(Triple.init).first,
                sdkRootDir: AbsolutePath(validating: destination.sdkRootDir, relativeTo: destinationDirectory),
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
                )
            )
        default:
            throw DestinationError.invalidSchemaVersion
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

    enum CodingKeys: CodingKey {
        case schemaVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try Version(
            versionString: container.decode(String.self, forKey: .schemaVersion),
            usesLenientParsing: true
        )
    }
}

/// Represents v1 schema of `destination.json` files used for cross-compilation.
private struct DecodedDestinationV1: Codable {
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
private struct DecodedDestinationV2: Codable {
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
private struct DecodedDestinationV3: Decodable {
    struct TripleProperties: Decodable {
        /// Path relative to `destination.json` containing SDK root.
        let sdkRootPath: String

        /// Path relative to `destination.json` containing Swift resources for dynamic linking.
        let swiftResourcesPath: String?

        /// Path relative to `destination.json` containing Swift resources for static linking.
        let swiftStaticResourcesPath: String?

        /// Array of paths relative to `destination.json` containing headers.
        let includeSearchPaths: [String]?

        /// Array of paths relative to `destination.json` containing libraries.
        let librarySearchPaths: [String]?

        /// Array of paths relative to `destination.json` containing toolset files.
        let toolsetPaths: [String]?
    }

    /// Mapping of triple strings to corresponding properties of such run-time triple.
    let runTimeTriples: [String: TripleProperties]
}
