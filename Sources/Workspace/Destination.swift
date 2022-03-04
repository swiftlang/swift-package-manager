/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import Foundation
import SPMBuildCore
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
    public var target: Triple?

    /// The architectures to build for. We build for host architecture if this is empty.
    public var archs: [String] = []

    /// The SDK used to compile for the destination.
    public var sdk: AbsolutePath?

    /// The binDir in the containing the compilers/linker to be used for the compilation.
    public var binDir: AbsolutePath

    /// Additional flags to be passed to the C compiler.
    public let extraCCFlags: [String]

    /// Additional flags to be passed to the Swift compiler.
    public let extraSwiftCFlags: [String]

    /// Additional flags to be passed when compiling with C++.
    public let extraCPPFlags: [String]

    /// Creates a compilation destination with the specified properties.
    public init(
        target: Triple? = nil,
        sdk: AbsolutePath?,
        binDir: AbsolutePath,
        extraCCFlags: [String] = [],
        extraSwiftCFlags: [String] = [],
        extraCPPFlags: [String] = []
    ) {
        self.target = target
        self.sdk = sdk
        self.binDir = binDir
        self.extraCCFlags = extraCCFlags
        self.extraSwiftCFlags = extraSwiftCFlags
        self.extraCPPFlags = extraCPPFlags
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
        return AbsolutePath(CommandLine.arguments[0], relativeTo: cwd).parentDirectory
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
            let sdkPathStr = try Process.checkNonZeroExit(
                arguments: ["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-path"], environment: environment).spm_chomp()
            guard !sdkPathStr.isEmpty else {
                throw DestinationError.invalidInstallation("default SDK not found")
            }
            sdkPath = AbsolutePath(sdkPathStr)
        }
#else
        sdkPath = nil
#endif

        // Compute common arguments for clang and swift.
        var extraCCFlags: [String] = []
        var extraSwiftCFlags: [String] = []
#if os(macOS)
        if let sdkPaths = Destination.sdkPlatformFrameworkPaths(environment: environment) {
            extraCCFlags += ["-F", sdkPaths.fwk.pathString]
            extraSwiftCFlags += ["-F", sdkPaths.fwk.pathString]
            extraSwiftCFlags += ["-I", sdkPaths.lib.pathString]
            extraSwiftCFlags += ["-L", sdkPaths.lib.pathString]
        }
#endif

#if !os(Windows)
        extraCCFlags += ["-fPIC"]
#endif

        var extraCPPFlags: [String] = []
#if os(macOS)
        extraCPPFlags += ["-lc++"]
#elseif os(Windows)
        extraCPPFlags += []
#else
        extraCPPFlags += ["-lstdc++"]
#endif

        return Destination(
            target: nil,
            sdk: sdkPath,
            binDir: binDir,
            extraCCFlags: extraCCFlags,
            extraSwiftCFlags: extraSwiftCFlags,
            extraCPPFlags: extraCPPFlags
        )
    }

    /// Returns macosx sdk platform framework path.
    public static func sdkPlatformFrameworkPaths(
        environment: EnvironmentVariables = .process()
    ) -> (fwk: AbsolutePath, lib: AbsolutePath)? {
        if let path = _sdkPlatformFrameworkPath {
            return path
        }
        let platformPath = try? Process.checkNonZeroExit(
            arguments: ["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-platform-path"],
            environment: environment).spm_chomp()

        if let platformPath = platformPath, !platformPath.isEmpty {
            // For XCTest framework.
            let fwk = AbsolutePath(platformPath).appending(
                components: "Developer", "Library", "Frameworks")

            // For XCTest Swift library.
            let lib = AbsolutePath(platformPath).appending(
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
            let wasiSysroot = host.binDir
                .parentDirectory // usr
                .appending(components: "share", "wasi-sysroot")
            return Destination(
                target: triple,
                sdk: wasiSysroot,
                binDir: host.binDir,
                extraCCFlags: [],
                extraSwiftCFlags: [],
                extraCPPFlags: []
            )
        }
        return nil
    }
}

extension Destination {
    /// Load a Destination description from a JSON representation from disk.
    public init(fromFile path: AbsolutePath, fileSystem: FileSystem) throws {
        let decoder = JSONDecoder.makeWithDefaults()
        let version = try decoder.decode(path: path, fileSystem: fileSystem, as: VersionInfo.self)
        // Check schema version.
        guard version.version == 1 else {
            throw DestinationError.invalidSchemaVersion
        }
        let destination = try decoder.decode(path: path, fileSystem: fileSystem, as: DestinationInfo.self)
        try self.init(
            target: destination.target.map{ try Triple($0) },
            sdk: destination.sdk,
            binDir: destination.binDir,
            extraCCFlags: destination.extraCCFlags,
            extraSwiftCFlags: destination.extraSwiftCFlags,
            extraCPPFlags: destination.extraCPPFlags
        )
    }
}

fileprivate struct VersionInfo: Codable {
    let version: Int
}

fileprivate struct DestinationInfo: Codable {
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
