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

public enum DestinationError: Swift.Error {
    /// Couldn't find the Xcode installation.
    case invalidInstallation(String)

    /// The schema version is invalid.
    case invalidSchemaVersion
}

extension DestinationError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidSchemaVersion:
            return "unsupported destination file schema version"
        case .invalidInstallation(let problem):
            return problem
        }
    }
}

/// The compilation destination, has information about everything that's required for a certain destination.
public struct Destination: Encodable, Equatable {

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
    public var archs: [String] = []

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
        get {
            toolchainBinDir
        }
        set {
            toolchainBinDir = newValue
        }
    }

    /// Path to a directory containing the toolchain (compilers/linker) to be used for the compilation.
    public var toolchainBinDir: AbsolutePath

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
    public var extraFlags: BuildFlags

    /// Creates a compilation destination with the specified properties.
    @available(*, deprecated, message: "use `init(targetTriple:sdkRootDir:toolchainBinDir:extraFlags)` instead")
    public init(
        target: Triple? = nil,
        sdk: AbsolutePath?,
        binDir: AbsolutePath,
        extraCCFlags: [String] = [],
        extraSwiftCFlags: [String] = [],
        extraCPPFlags: [String]
    ) {
        self.hostTriple = nil
        self.targetTriple = target
        self.sdkRootDir = sdk
        self.toolchainBinDir = binDir
        self.extraFlags = BuildFlags(
            cCompilerFlags: extraCCFlags,
            cxxCompilerFlags: extraCPPFlags,
            swiftCompilerFlags: extraSwiftCFlags
        )
    }
    
    /// Creates a compilation destination with the specified properties.
    public init(
        hostTriple: Triple? = nil,
        targetTriple: Triple? = nil,
        sdkRootDir: AbsolutePath?,
        toolchainBinDir: AbsolutePath,
        extraFlags: BuildFlags = BuildFlags()
    ) {
        self.hostTriple = hostTriple
        self.targetTriple = targetTriple
        self.sdkRootDir = sdkRootDir
        self.toolchainBinDir = toolchainBinDir
        self.extraFlags = extraFlags
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
        environment: [String:String] = ProcessEnv.vars
    ) throws -> Destination {
        let originalWorkingDirectory = originalWorkingDirectory ?? localFileSystem.currentWorkingDirectory
        // Select the correct binDir.
        if ProcessEnv.vars["SWIFTPM_CUSTOM_BINDIR"] != nil {
            print("SWIFTPM_CUSTOM_BINDIR was deprecated in favor of SWIFTPM_CUSTOM_BIN_DIR")
        }
        let customBinDir = (ProcessEnv.vars["SWIFTPM_CUSTOM_BIN_DIR"] ?? ProcessEnv.vars["SWIFTPM_CUSTOM_BINDIR"])
            .flatMap{ try? AbsolutePath(validating: $0) }
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
                arguments: ["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-path"], environment: environment).spm_chomp()
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
        if let sdkPaths = try Destination.sdkPlatformFrameworkPaths(environment: environment) {
            extraCCFlags += ["-F", sdkPaths.fwk.pathString]
            extraSwiftCFlags += ["-F", sdkPaths.fwk.pathString]
            extraSwiftCFlags += ["-I", sdkPaths.lib.pathString]
            extraSwiftCFlags += ["-L", sdkPaths.lib.pathString]
        }
#endif

#if !os(Windows)
        extraCCFlags += ["-fPIC"]
#endif

        return Destination(
            sdkRootDir: sdkPath,
            toolchainBinDir: binDir,
            extraFlags: BuildFlags(cCompilerFlags: extraCCFlags, swiftCompilerFlags: extraSwiftCFlags)
        )
    }

    /// Returns macosx sdk platform framework path.
    public static func sdkPlatformFrameworkPaths(
        environment: EnvironmentVariables = .process()
    ) throws -> (fwk: AbsolutePath, lib: AbsolutePath)? {
        if let path = _sdkPlatformFrameworkPath {
            return path
        }
        let platformPath = try? TSCBasic.Process.checkNonZeroExit(
            arguments: ["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-platform-path"],
            environment: environment).spm_chomp()

        if let platformPath = platformPath, !platformPath.isEmpty {
            // For XCTest framework.
            let fwk = try AbsolutePath(validating: platformPath).appending(
                components: "Developer", "Library", "Frameworks")

            // For XCTest Swift library.
            let lib = try AbsolutePath(validating: platformPath).appending(
                components: "Developer", "usr", "lib")

            _sdkPlatformFrameworkPath = (fwk, lib)
        }
        return _sdkPlatformFrameworkPath
    }

    /// Cache storage for sdk platform path.
    private static var _sdkPlatformFrameworkPath: (fwk: AbsolutePath, lib: AbsolutePath)? = nil

    /// Returns a default destination of a given target environment
    public static func defaultDestination(for triple: Triple, host: Destination) -> Destination? {
        if triple.isWASI() {
            let wasiSysroot = host.toolchainBinDir
                .parentDirectory // usr
                .appending(components: "share", "wasi-sysroot")
            return Destination(
                targetTriple: triple,
                sdkRootDir: wasiSysroot,
                toolchainBinDir: host.toolchainBinDir
            )
        }
        return nil
    }
}

extension Destination {
    /// Load a ``Destination`` description from a JSON representation from disk.
    public init(fromFile path: AbsolutePath, fileSystem: FileSystem) throws {
        let decoder = JSONDecoder.makeWithDefaults()
        let version = try decoder.decode(path: path, fileSystem: fileSystem, as: VersionInfo.self)
        
        // Check schema version.
        switch version.version {
        case 1:
            let destination = try decoder.decode(path: path, fileSystem: fileSystem, as: DestinationInfoV1.self)
            try self.init(
                targetTriple: destination.target.map{ try Triple($0) },
                sdkRootDir: destination.sdk,
                toolchainBinDir: destination.binDir,
                extraFlags: .init(
                    cCompilerFlags: destination.extraCCFlags,
                    cxxCompilerFlags: destination.extraCPPFlags,
                    swiftCompilerFlags: destination.extraSwiftCFlags
                )
            )
        case 2:
            let destination = try decoder.decode(path: path, fileSystem: fileSystem, as: DestinationInfoV2.self)
            let destinationDirectory = path.parentDirectory

            // TODO support multiple host and destination triple.
            try self.init(
                hostTriple: destination.hostTriples.map(Triple.init).first,
                targetTriple: destination.targetTriples.map(Triple.init).first,
                sdkRootDir: AbsolutePath(validating: destination.sdkRootDir, relativeTo: destinationDirectory),
                toolchainBinDir: AbsolutePath(validating: destination.toolchainBinDir, relativeTo: destinationDirectory),
                extraFlags: .init(
                    cCompilerFlags: destination.extraCCFlags,
                    cxxCompilerFlags: destination.extraCXXFlags,
                    swiftCompilerFlags: destination.extraSwiftCFlags,
                    linkerFlags: destination.extraLinkerFlags
                )
            )
        default:
            throw DestinationError.invalidSchemaVersion
        }
    }
}

/// Version of the schema of `destination.json` files used for cross-compilation.
fileprivate struct VersionInfo: Codable {
    let version: Int
}

/// Represents v1 schema of `destination.json` files used for cross-compilation.
fileprivate struct DestinationInfoV1: Codable {
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
fileprivate struct DestinationInfoV2: Codable {
    let sdkRootDir: String
    let toolchainBinDir: String
    let hostTriples: [String]
    let targetTriples: [String]
    let extraCCFlags: [String]
    let extraSwiftCFlags: [String]
    let extraCXXFlags: [String]
    let extraLinkerFlags: [String]
}
