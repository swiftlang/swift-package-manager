/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import POSIX

import Basic
import protocol Build.Toolchain
import Utility

#if os(macOS)
    private let whichClangArgs = ["xcrun", "--find", "clang"]
#else
    private let whichClangArgs = ["which", "clang"]
#endif

struct UserToolchain: Toolchain {
    /// Path of the `swiftc` compiler.
    let swiftCompiler: AbsolutePath
    
    /// Path of the `clang` compiler.
    let clangCompiler: AbsolutePath

    /// Path to llbuild.
    let llbuild: AbsolutePath

    /// Path to SwiftPM library directory containing runtime libraries.
    let libDir: AbsolutePath
    
    /// Path of the default SDK (a.k.a. "sysroot"), if any.
    let defaultSDK: AbsolutePath?

  #if os(macOS)
    /// Path to the sdk platform framework path.
    let sdkPlatformFrameworksPath: AbsolutePath

    var clangPlatformArgs: [String] {
        return ["-arch", "x86_64", "-mmacosx-version-min=10.10", "-isysroot", defaultSDK!.asString, "-F", sdkPlatformFrameworksPath.asString]
    }
    var swiftPlatformArgs: [String] {
        return ["-target", "x86_64-apple-macosx10.10", "-sdk", defaultSDK!.asString, "-F", sdkPlatformFrameworksPath.asString]
    }
  #else
    let clangPlatformArgs: [String] = ["-fPIC"]
    let swiftPlatformArgs: [String] = []
  #endif

    init() throws {
        // Get the search paths from PATH.
        let envSearchPaths = UserToolchain.getEnvSearchPaths(
            pathString: getenv("PATH"), currentWorkingDirectory: currentWorkingDirectory)

        func lookup(env: String) -> AbsolutePath? {
            return UserToolchain.lookupExecutablePath(
                inEnvValue: getenv(env),
                searchPaths: envSearchPaths)
        }

      #if Xcode
        // For Xcode, set bin directory to the build directory containing the fake
        // toolchain created during bootstraping. This is obviously not production ready
        // and only exists as a development utility right now.
        //
        // This also means that we should have bootstrapped with the same Swift toolchain
        // we're using inside Xcode otherwise we will not be able to load the runtime libraries.
        //
        // FIXME: We may want to allow overriding this using an env variable but that
        // doesn't seem urgent or extremely useful as of now.
        let binDir = AbsolutePath(#file).parentDirectory
            .parentDirectory.parentDirectory.appending(components: ".build", "debug")
      #else
        let binDir = AbsolutePath(
            CommandLine.arguments[0], relativeTo: currentWorkingDirectory).parentDirectory
      #endif

        libDir = binDir.parentDirectory.appending(components: "lib", "swift", "pm")

        // First look in env and then in bin dir.
        swiftCompiler = lookup(env: "SWIFT_EXEC") ?? binDir.appending(component: "swiftc")
        
        // Check that it's valid in the file system.
        // FIXME: We should also check that it resolves to an executable file
        //        (it could be a symlink to such as file).
        guard localFileSystem.exists(swiftCompiler) else {
            throw Error.invalidToolchain(problem: "could not find `swiftc` at expected path \(swiftCompiler.asString)")
        }

        // Look for llbuild in bin dir.
        llbuild = binDir.appending(component: "swift-build-tool")
        guard localFileSystem.exists(llbuild) else {
            throw Error.invalidToolchain(problem: "could not find `llbuild` at expected path \(llbuild.asString)")
        }

        // Find the Clang compiler, looking first in the environment.
        if let value = lookup(env: "CC") {
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
        // FIXME: We should also check that it resolves to an executable file
        //        (it could be a symlink to such as file).
        guard localFileSystem.exists(clangCompiler) else {
            throw Error.invalidToolchain(problem: "could not find `clang` at expected path \(clangCompiler.asString)")
        }
        
        // Find the default SDK (on macOS only).
      #if os(macOS)
        let sdk: AbsolutePath

        if let value = UserToolchain.lookupExecutablePath(inEnvValue: getenv("SYSROOT")) {
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
        
        // FIXME: We should probably also check that it is a directory, etc.
        guard localFileSystem.exists(sdk) else {
            throw Error.invalidToolchain(problem: "could not find default SDK at expected path \(sdk.asString)")
        }
        defaultSDK = sdk

        let platformPath = try Process.checkNonZeroExit(
            args: "xcrun", "--sdk", "macosx", "--show-sdk-platform-path").chomp()
        guard !platformPath.isEmpty else {
                throw Error.invalidToolchain(problem: "could not get sdk platform path")
        }
        sdkPlatformFrameworksPath = AbsolutePath(platformPath).appending(components: "Developer", "Library", "Frameworks")
      #else
        defaultSDK = nil
      #endif
    }

    /// Computes search paths from PATH variable.
    ///
    /// - Parameters:
    ///   - pathString: The path string to parse.
    ///   - currentWorkingDirectory: The current working directory, the relative paths will be converted to absolute paths based on this path.
    /// - Returns: List of search paths.
    static func getEnvSearchPaths(
        pathString: String?,
        currentWorkingDirectory cwd: AbsolutePath
    ) -> [AbsolutePath] {
        // Compute search paths from PATH variable.
        return (pathString ?? "").characters.split(separator: ":").map(String.init).map { pathString in
            // If this is an absolute path, we're done.
            if pathString.characters.first == "/" {
                return AbsolutePath(pathString)
            }
            // Otherwise convert it into absolute path relative to the working directory.
            return AbsolutePath(pathString, relativeTo: cwd)
        }
    }

    /// Lookup an executable path from environment variable value. This method searches in the following order:
    /// * If env value is a valid absolute path, return it.
    /// * If env value is relative path, first try to locate it in current working directory.
    /// * Otherwise, in provided search paths.
    ///
    /// - Parameters:
    ///   - value: The value from environment variable.
    ///   - cwd: The current working directory to look in.
    ///   - searchPath: The additional search path to look in if not found in cwd.
    /// - Returns: Valid path to executable if present, otherwise nil.
    static func lookupExecutablePath(
        inEnvValue value: String?,
        currentWorkingDirectory cwd: AbsolutePath = currentWorkingDirectory,
        searchPaths: [AbsolutePath] = []
    ) -> AbsolutePath? {
        // We should have a value to continue.
        guard let value = value, !value.isEmpty else {
            return nil
        }
        // We have a value, but it could be an absolute or a relative path.
        let path = AbsolutePath(value, relativeTo: cwd)
        if exists(path) {
            return path
        }
        // Ensure the value is not a path.
        guard !value.characters.contains("/") else {
            return nil
        }
        // Try to locate in search paths.
        for path in searchPaths {
            let exec = path.appending(component: value)
            if exists(exec) {
                return exec
            }
        }
        return nil
    }
}
