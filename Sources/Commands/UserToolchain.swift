/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import POSIX

import Basic
import Build
import PackageLoading
import protocol Build.Toolchain
import Utility

#if os(macOS)
    private let whichClangArgs = ["xcrun", "--find", "clang"]
#else
    private let whichClangArgs = ["which", "clang"]
#endif

/// Concrete object for manifest resource provider.
private struct UserManifestResources: ManifestResourceProvider {
    let swiftCompiler: AbsolutePath
    let libDir: AbsolutePath
    let sdkRoot: AbsolutePath?
}

public struct UserToolchain: Toolchain {

    /// The manifest resource provider.
    public let manifestResources: ManifestResourceProvider

    /// Path of the `swiftc` compiler.
    public let swiftCompiler: AbsolutePath

    /// Path of the `clang` compiler.
    public let clangCompiler: AbsolutePath

    public let extraCCFlags: [String]

    public let extraSwiftCFlags: [String]

    public var extraCPPFlags: [String] {
        return destination.extraCPPFlags
    }

    public var dynamicLibraryExtension: String {
        return destination.dynamicLibraryExtension
    }

    /// Path of the `swift` interpreter.
    public var swiftInterpreter: AbsolutePath {
        return swiftCompiler.parentDirectory.appending(component: "swift")
    }

    /// Path to llbuild.
    let llbuild: AbsolutePath

    /// The compilation destination object.
    let destination: Destination

    public init(destination: Destination) throws {
        self.destination = destination

        // Get the search paths from PATH.
        let envSearchPaths = getEnvSearchPaths(
            pathString: getenv("PATH"), currentWorkingDirectory: currentWorkingDirectory)

        func lookup(fromEnv: String) -> AbsolutePath? {
            return lookupExecutablePath(
                filename: getenv(fromEnv),
                searchPaths: envSearchPaths)
        }

        // Get the binDir from destination.
        let binDir = lookup(fromEnv: "SWIFT_EXEC")?.appending(components: "..") ?? destination.binDir

        // Find swift compiler in the bin directory.
        let swiftCompiler = binDir.appending(component: "swiftc")

        // Check that it's valid in the file system.
        guard localFileSystem.isExecutableFile(swiftCompiler) else {
            throw Error.invalidToolchain(problem: "could not find `swiftc` at expected path \(swiftCompiler.asString)")
        }

        // Check if compiler only swift compiler is present.
        //
        // This is useful for compiler developers who wants to use SwiftPM from a toolchain but a
        // custom built compiler.
        let compileOnlySwiftCompiler = lookup(fromEnv: "SWIFT_EXEC_COMPILE_ONLY")
        if let compileOnlySwiftCompiler = compileOnlySwiftCompiler {
            guard localFileSystem.isExecutableFile(compileOnlySwiftCompiler) else {
                throw Error.invalidToolchain(problem: "could not find `swiftc` at expected path \(compileOnlySwiftCompiler.asString)")
            }
        }

        self.swiftCompiler = compileOnlySwiftCompiler ?? swiftCompiler

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

        self.extraSwiftCFlags = [
            "-target", destination.target,
            "-sdk", destination.sdk.asString
        ] + destination.extraSwiftCFlags

        self.extraCCFlags = [
            "-target", destination.target,
            "--sysroot", destination.sdk.asString
        ] + destination.extraCCFlags

        manifestResources = UserManifestResources(
            // Always use the default compiler (and not compile only swift compiler) for parsing the manifests.
            swiftCompiler: swiftCompiler,
            libDir: binDir.parentDirectory.appending(components: "lib", "swift", "pm"),
            sdkRoot: self.destination.sdk
        )
    }
}
