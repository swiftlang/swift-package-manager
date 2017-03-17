/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import POSIX

import Basic
import PackageLoading
import protocol Build.Toolchain
import Utility

#if os(macOS)
    private let whichClangArgs = ["xcrun", "--find", "clang"]
#else
    private let whichClangArgs = ["which", "clang"]
#endif

public struct UserToolchain: Toolchain, ManifestResourceProvider {
    /// Path of the `swiftc` compiler.
    public let swiftCompiler: AbsolutePath
    
    /// Path of the `clang` compiler.
    public let clangCompiler: AbsolutePath

    /// Path to llbuild.
    let llbuild: AbsolutePath

    /// Path to SwiftPM library directory containing runtime libraries.
    public let libDir: AbsolutePath

    /// Path to share directory in toolchain.
    public let shareDir: AbsolutePath
    
    /// Path to the directory containing sandbox files.
    public var sandboxProfileDir: AbsolutePath {
        return shareDir.appending(component: "sandbox")
    }

    /// Path of the default SDK (a.k.a. "sysroot"), if any.
    public let defaultSDK: AbsolutePath?

  #if os(macOS)
    /// Path to the sdk platform framework path.
    public let sdkPlatformFrameworksPath: AbsolutePath?

    public var clangPlatformArgs: [String] {
        var args = ["-arch", "x86_64", "-mmacosx-version-min=10.10", "-isysroot", defaultSDK!.asString]
        if let sdkPlatformFrameworksPath = sdkPlatformFrameworksPath {
            args += ["-F", sdkPlatformFrameworksPath.asString]
        }
        return args
    }
    public var swiftPlatformArgs: [String] {
        var args = ["-target", "x86_64-apple-macosx10.10", "-sdk", defaultSDK!.asString]
        if let sdkPlatformFrameworksPath = sdkPlatformFrameworksPath {
            args += ["-F", sdkPlatformFrameworksPath.asString]
        }
        return args
    }
  #else
    public let clangPlatformArgs: [String] = ["-fPIC"]
    public let swiftPlatformArgs: [String] = []
  #endif

    public init(_ binDir: AbsolutePath) throws {
        // Get the search paths from PATH.
        let envSearchPaths = Utility.getEnvSearchPaths(
            pathString: getenv("PATH"), currentWorkingDirectory: currentWorkingDirectory)

        func lookup(fromEnv: String) -> AbsolutePath? {
            return Utility.lookupExecutablePath(
                filename: getenv(fromEnv),
                searchPaths: envSearchPaths)
        }

        libDir = binDir.parentDirectory.appending(components: "lib", "swift", "pm")
        shareDir = binDir.parentDirectory.appending(components: "share", "swift", "pm")

        // First look in env and then in bin dir.
        swiftCompiler = lookup(fromEnv: "SWIFT_EXEC") ?? binDir.appending(component: "swiftc")
        
        // Check that it's valid in the file system.
        guard localFileSystem.isExecutableFile(swiftCompiler) else {
            throw Error.invalidToolchain(problem: "could not find `swiftc` at expected path \(swiftCompiler.asString)")
        }

        // Look for llbuild in bin dir.
        llbuild = binDir.appending(component: "swift-build-tool")
        guard localFileSystem.exists(llbuild) else {
            throw Error.invalidToolchain(problem: "could not find `llbuild` at expected path \(llbuild.asString)")
        }

        // Find the Clang compiler, looking first in the environment.
        if let value = lookup(fromEnv: "CC") {
            clangCompiler = value
        } else {
            // No value in env, so search for `clang`.
            let foundPath = try Process.checkNonZeroExit(arguments: whichClangArgs).chomp()
            guard !foundPath.isEmpty else {
                throw Error.invalidToolchain(problem: "could not find `clang`")
            }
            clangCompiler = AbsolutePath(foundPath)
        }
        
        // Check that it's valid in the file system.
        guard localFileSystem.isExecutableFile(clangCompiler) else {
            throw Error.invalidToolchain(problem: "could not find `clang` at expected path \(clangCompiler.asString)")
        }
        
        // Find the default SDK (on macOS only).
      #if os(macOS)
        let sdk: AbsolutePath

        if let value = Utility.lookupExecutablePath(filename: getenv("SYSROOT")) {
            sdk = value
        } else {
            // No value in env, so search for it.
            let foundPath = try Process.checkNonZeroExit(
                args: "xcrun", "--sdk", "macosx", "--show-sdk-path").chomp()
            guard !foundPath.isEmpty else {
                throw Error.invalidToolchain(problem: "could not find default SDK")
            }
            sdk = AbsolutePath(foundPath)
        }
        
        // Verify that the sdk exists and is a directory
        guard localFileSystem.exists(sdk) && localFileSystem.isDirectory(sdk) else {
            throw Error.invalidToolchain(problem: "could not find default SDK at expected path \(sdk.asString)")
        }
        defaultSDK = sdk

        // Try to get the platform path.
        let platformPath = try? Process.checkNonZeroExit(
            args: "xcrun", "--sdk", "macosx", "--show-sdk-platform-path").chomp()
        if let platformPath = platformPath, !platformPath.isEmpty {
            sdkPlatformFrameworksPath = AbsolutePath(platformPath).appending(components: "Developer", "Library", "Frameworks")
        } else {
            sdkPlatformFrameworksPath = nil
        }
      #else
        defaultSDK = nil
      #endif
    }

}
