/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import class Foundation.ProcessInfo

import POSIX

import Basic
import protocol Build.Toolchain

#if os(macOS)
    private let whichClangArgs = ["xcrun", "--find", "clang"]
    private let whichDefaultSDKArgs = ["xcrun", "--sdk", "macosx", "--show-sdk-path"]
#else
    private let whichClangArgs = ["which", "clang"]
#endif

struct UserToolchain: Toolchain {
    /// Path of the `swiftc` compiler.
    let swiftCompiler: AbsolutePath
    
    /// Path of the `clang` compiler.
    let clangCompiler: AbsolutePath
    
    /// Path of the default SDK (a.k.a. "sysroot"), if any.
    let defaultSDK: AbsolutePath?

#if os(macOS)
    var clangPlatformArgs: [String] {
        return ["-arch", "x86_64", "-mmacosx-version-min=10.10", "-isysroot", defaultSDK!.asString]
    }
    var swiftPlatformArgs: [String] {
        return ["-target", "x86_64-apple-macosx10.10", "-sdk", defaultSDK!.asString]
    }
#else
    let clangPlatformArgs: [String] = []
    let swiftPlatformArgs: [String] = []
#endif

    /// Lookup an executable path from environment variable value. This method searches in the following order:
    /// * If env value is a valid abolsute path, return it.
    /// * If env value is relative path, first try to locate it in current working directory.
    /// * Otherwise, in provided search paths.
    ///
    /// - Parameters:
    ///   - value: The value from environment variable.
    ///   - cwd: The current working directory to look in.
    ///   - searchPath: The addtional search path to look in if not found in cwd.
    /// - Returns: Valid path to executable if present, otherwise nil.
    static func lookupExecutablePath(inEnvValue value: String?, currentWorkingDirectory cwd: AbsolutePath, searchPaths: [AbsolutePath]) -> AbsolutePath? {
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

    /// Computes search paths from PATH variable.
    ///
    /// - Parameters:
    ///   - pathString: The path string to parse.
    ///   - currentWorkingDirectory: The current working directory, the relative paths will be converted to absolute paths based on this path.
    /// - Returns: List of search paths.
    static func getEnvSearchPaths(pathString: String?, currentWorkingDirectory cwd: AbsolutePath) -> [AbsolutePath] {
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

    init() throws {
        // Get the search paths from PATH.
        let envSearchPaths = UserToolchain.getEnvSearchPaths(pathString: getenv("PATH"), currentWorkingDirectory: currentWorkingDirectory)

        func lookup(env: String) -> AbsolutePath? {
            return UserToolchain.lookupExecutablePath(inEnvValue: getenv(env), currentWorkingDirectory: currentWorkingDirectory, searchPaths: envSearchPaths)
        }

        // Find the Swift compiler, looking first in the environment.
        if let value = lookup(env: "SWIFT_EXEC") {
            swiftCompiler = value
        }
        else {
            // No value in env, so look for `swiftc` alongside our own binary.
            swiftCompiler = AbsolutePath(CommandLine.arguments[0], relativeTo: currentWorkingDirectory).parentDirectory.appending(component: "swiftc")
        }
        
        // Check that it's valid in the file system.
        // FIXME: We should also check that it resolves to an executable file
        //        (it could be a symlink to such as file).
        guard localFileSystem.exists(swiftCompiler) else {
            throw Error.invalidToolchain(problem: "could not find `swiftc` at expected path \(swiftCompiler.asString)")
        }
        
        // Find the Clang compiler, looking first in the environment.
        if let value = lookup(env: "CC") {
            clangCompiler = value
        }
        else {
            // No value in env, so search for `clang`.
            guard let foundPath = try? POSIX.popen(whichClangArgs, environment: ProcessInfo.processInfo.environment).chomp(), !foundPath.isEmpty else {
                throw Error.invalidToolchain(problem: "could not find `clang`")
            }
            clangCompiler = AbsolutePath(foundPath, relativeTo: currentWorkingDirectory)
        }
        
        // Check that it's valid in the file system.
        // FIXME: We should also check that it resolves to an executable file
        //        (it could be a symlink to such as file).
        guard localFileSystem.exists(clangCompiler) else {
            throw Error.invalidToolchain(problem: "could not find `clang` at expected path \(clangCompiler.asString)")
        }
        
        // Find the default SDK (on macOS only).
      #if os(macOS)
        if let value = UserToolchain.lookupExecutablePath(inEnvValue: getenv("SYSROOT"), currentWorkingDirectory: currentWorkingDirectory, searchPaths: []) {
            defaultSDK = value
        }
        else {
            // No value in env, so search for it.
            guard let foundPath = try? POSIX.popen(whichDefaultSDKArgs, environment: ProcessInfo.processInfo.environment).chomp(), !foundPath.isEmpty else {
                throw Error.invalidToolchain(problem: "could not find default SDK")
            }
            defaultSDK = AbsolutePath(foundPath, relativeTo: currentWorkingDirectory)
        }
        
        // If we have an SDK, we check that it's valid in the file system.
        if let sdk = defaultSDK {
            // FIXME: We should probably also check that it is a directory, etc.
            guard localFileSystem.exists(sdk) else {
                throw Error.invalidToolchain(problem: "could not find default SDK at expected path \(sdk.asString)")
            }
        }
      #else
        defaultSDK = nil
      #endif
    }
}
