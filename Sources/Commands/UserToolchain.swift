/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

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

    init() throws {
        // Find the Swift compiler, looking first in the environment.
        if let value = getenv("SWIFT_EXEC"), !value.isEmpty {
            // We have a value, but it could be an absolute or a relative path.
            swiftCompiler = AbsolutePath(value, relativeTo: currentWorkingDirectory)
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
        if let value = getenv("CC"), !value.isEmpty {
            // We have a value, but it could be an absolute or a relative path.
            clangCompiler = AbsolutePath(value, relativeTo: currentWorkingDirectory)
        }
        else {
            // No value in env, so search for `clang`.
            guard let foundPath = try? POSIX.popen(whichClangArgs).chomp(), !foundPath.isEmpty else {
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
        if let value = getenv("SYSROOT"), !value.isEmpty {
            // We have a value, but it could be an absolute or a relative path.
            defaultSDK = AbsolutePath(value, relativeTo: currentWorkingDirectory)
        }
        else {
            // No value in env, so search for it.
            guard let foundPath = try? POSIX.popen(whichDefaultSDKArgs).chomp(), !foundPath.isEmpty else {
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
